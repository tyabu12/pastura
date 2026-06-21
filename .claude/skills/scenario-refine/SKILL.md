---
name: scenario-refine
description: Run one scenario-refine cycle — evaluate a rotating slice of the EXISTING shipped scenario inventory (bundled presets + gallery) on pastura-harness with real local-LLM inference, judge each against a category-aware rubric with regression detection, auto-generate and A/B-test v2 improvement candidates for low scorers, and append the local audit journal. Use when the user asks to run scenario-refine, evaluate or polish existing scenarios, audit the scenario inventory, or check for scenario quality regressions.
allowed-tools: Read, Write, Grep, Glob, Bash
---

# /scenario-refine

One full refine cycle: **select → run → judge (regression) → improve (A/B)
→ journal**. The sibling of `/scenario-factory`: where factory *generates*
fresh scenarios, refine *evaluates and polishes the existing shipped
inventory*. Run from the repository root.

Optional args:

- `only: <id,...>` — restrict the cycle to the named scenarios (skip the
  rotation), e.g. to re-check one preset on demand.
- `force-improve: <id,...>` — generate an A/B v2 for the named scenarios even
  if they are NOT low scorers (Step 4), to probe whether a high scorer can be
  pushed higher.

## Safety boundary (read first)

**This skill writes ONLY under `data/factory/` (run logs, A/B candidate
YAMLs, the journal — all gitignored).** It MUST NEVER edit
`Pastura/Pastura/Resources/Presets/` or `docs/gallery/` — those are its
read-only *inputs*. Any write outside `data/factory/` is a skill bug: abort
the cycle and report it. The skill makes no `git` commits and no `git push` /
`gh` calls, so even an errant write stays a dirty working tree and can never
reach users. `allowed-tools` deliberately omits `Edit` — refine never edits a
file in place; the only writes are new candidate YAMLs and the journal.

Actually changing a shipped scenario is a SEPARATE, human-driven step (see
§ Promotion) — never automated by this skill or its Routine.

## Non-goals

- **No direct inventory edits.** See the safety boundary above.
- **No promotion / swap automation.** The journal is a judging log. Promoting
  or retiring a scenario is a human-reviewed `/orchestrate` PR (§ Promotion).
- **No content-safety screening.** The judge scores quality only. Safety is
  enforced by the blocklist pre-commit gate at preset-promotion time and by
  hand-curation for the gallery (same as factory).
- **No external LLM APIs.** Selection, judging, and v2 generation are done by
  THIS session. Only the local harness (llama.cpp + bundled GGUF) burns
  inference.
- **No scheduled execution self-registration.** Scheduling is an operator
  action (§ Scheduling).

## Constants

- `MODEL`: `~/Models/gemma-4-E2B-it-Q4_K_M.gguf` (sha256 matches the
  `ModelRegistry` pin). Pass its stem `gemma-4-E2B-it-Q4_K_M` as the journal
  `model` so the baseline delta keys on it — a model swap re-evaluates the
  inventory from scratch.
- `DATE`: today as `YYYY-MM-DD`.
- `COUNT`: scenarios to evaluate this cycle (rotation slice). Default `5`
  (≈10-15 min before A/B). Running the whole ~21-scenario inventory nightly
  would take ≈45-90 min; the rotation re-checks the oldest slice instead.
- Journal: `data/factory/audit-digest.md` (gitignored local log — appended in
  place, never committed; bootstrapped by `append_audit.py` if absent).
- Run logs: `data/factory/audit-runs/<DATE>/<id>.jsonl` (gitignored; harness
  stderr lands in a `.stderr.log` sidecar — separate from factory's `runs/`).
- A/B candidates: `data/factory/improvements/<DATE>/<id>__v2.yaml` (gitignored).
- Per-run timeout: `600` seconds.
- Helper scripts: `.claude/skills/scenario-refine/scripts/` (this skill) plus
  **two shared scripts borrowed from the factory** (not duplicated):
  `.claude/skills/scenario-factory/scripts/run_scenario.sh` and
  `format_transcript.py`. This is a cross-skill dependency — a factory
  refactor that moves/renames those breaks this skill (Step 0 checks they
  exist).

## Step 0 — Preflight

1. `ls ~/Models/gemma-4-E2B-it-Q4_K_M.gguf` — abort with a clear message if
   the model is missing.
2. `command -v jq` — required by the run wrapper and the helper scripts.
3. `ls .claude/skills/scenario-factory/scripts/run_scenario.sh .claude/skills/scenario-factory/scripts/format_transcript.py`
   — abort if the borrowed factory scripts are gone (cross-skill dependency).
4. `swift build` once to warm the harness build (incremental afterwards). A
   build failure aborts the cycle — report it, do not run.

## Step 1 — Select the rotation slice

```bash
python3 .claude/skills/scenario-refine/scripts/select_inventory.py \
  --count 5 --model gemma-4-E2B-it-Q4_K_M
```

Emits a JSON array of the `COUNT` least-recently-evaluated scenarios (joining
the inventory with the journal), each with `id`, `path`, `channel`
(`preset` / `gallery`), `language`, `category`, `payoff_axis`, and
`last_evaluated`. Notes:

- **Rotation**: never-evaluated and oldest scenarios come first. en siblings
  are a lower tier (ja/non-en primaries are evaluated first; en is sampled).
- **`payoff_axis`** tells the judge which 4th axis to score (Step 3).
- First run (absent journal) treats everything as never-evaluated — expected.

Read the array; this is the cycle's worklist.

## Step 2 — Run each scenario on the harness

Sequentially (one model in RAM at a time), for each selected scenario, using
the scenario's own `path` (read-only — do NOT copy it into `data/factory/`):

```bash
bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
  <path-from-step-1> \
  ~/Models/gemma-4-E2B-it-Q4_K_M.gguf \
  data/factory/audit-runs/<DATE>/<id>.jsonl 600
```

The wrapper prints one JSON status line (`status`: `ok` / `failed` /
`config_error`) and always exits 0 — parse it, record it, move on. Crash
tolerance is the contract (#253): a `failed` run keeps its partial JSONL +
`.stderr.log`; do NOT retry in-cycle. Use a generous Bash timeout
(≥ 900 000 ms) or `run_in_background` per run; expect ~4–10 min each.

A `config_error` on a *shipped* scenario is a real signal (the inventory YAML
no longer validates, or its inference estimate exceeds the harness hard block)
— record it; it surfaces in the journal as a non-`ok` row to investigate.

## Step 3 — Judge in-session (category-aware + regression)

For each run with `status == ok`:

```bash
python3 .claude/skills/scenario-factory/scripts/format_transcript.py \
  data/factory/audit-runs/<DATE>/<id>.jsonl
```

Read the transcript and score the rubric — each axis 1–5 plus a one-line
comment. The **first three axes are universal**; the **4th
(`payoff_axis` from Step 1) depends on the scenario's category**:

| Axis (key) | What 5 looks like | What 1 looks like |
|---|---|---|
| (a) `coherence` | Outputs consistently honor premise & personas | Agents ignore the setting |
| (b) `interaction` | Agents react to each other; votes track content | Parallel monologues |
| (c) `breakdown_free` | No format breaks, language drift, or nonsense loops | Frequent breakdowns |
| (d) `payoff` — category-specific | (see below) | flat / absent |

4th-axis (`payoff`) meaning by category:

| category | `payoff_axis` | A 5 looks like |
|---|---|---|
| `creative` | `humor` | Genuinely funny lines a human would quote |
| `game_theory` | `strategic_tension` | Strategies diverge; real push-and-pull |
| `ethics` | `moral_divergence` | Positions split; moral reasoning surfaces |
| `social_psychology` | `phenomenon_visible` | The studied effect (e.g. conformity) is observable |
| `roleplay` | `narrative_engagement` | A scene you'd keep reading |
| `experimental` / other | `overall_engagement` | Worth running again |

Store scores under the fixed key `payoff` (the variable axis *name* travels in
`payoff_axis`), so the journal schema stays stable across categories.

**Failed / config_error runs get NO scores** — record the status and the
wrapper's `error` (skim the partial transcript only to classify the failure).
They are excluded from the baseline delta by `append_audit.py`, so a #253
crash never reads as a quality regression.

Regression awareness: `select_inventory.py`'s `last_evaluated` and the
journal's prior scores let you see whether a scenario is being re-checked. The
actual Δ (vs the prior same-id+model ok run) is computed by `append_audit.py`
and flagged `⚠️` when the 4-axis total drops by ≥ 2 — call out any such
regression in Step 6.

## Step 4 — Improve (A/B), bounded

For low scorers, generate ONE v2 candidate and A/B-test it. A scenario is an
**improvement candidate** when, this cycle, its total (max 20) ≤ 12, OR
`coherence` ≤ 2, OR `breakdown_free` ≤ 2, OR it regressed (`⚠️`). **Cap at 3
candidates per cycle** (inference budget) — pick the lowest scorers; log any
skipped over the cap (no silent truncation).

**Forced exploration (`force-improve`).** When invoked with a force list (the
`force-improve:` arg, or a plain-language request to A/B specific scenarios
regardless of score), generate a v2 for each named scenario even if it is a
high scorer — to probe whether it can be pushed higher. Forced candidates
still obey the 3-candidate cap, still land in `improvements/`, and are never
auto-promoted. Note `forced` in the candidate's comment so the journal
distinguishes a forced probe (which often loses — a valid, informative result)
from a score-triggered repair. A forced v2 that does NOT beat its baseline
(`vs base ≤ 0`) is evidence the current design is near-optimal for this model,
not a failure of the cycle.

For each chosen baseline:

1. Read the baseline YAML (read-only). Diagnose the weakest axis from the
   transcript.
2. Write a v2 targeting that axis to
   `data/factory/improvements/<DATE>/<id>__v2.yaml` with `id: <id>__v2`. Vary
   *mechanics* (persona differentiation, output-field constraints, round/topic
   structure — see the factory's generation learnings), not just topic
   strings. Keep the inference estimate ≤ 50 (the wrapper hard-blocks > 100).
   **This is the only YAML the skill writes, and it goes under
   `data/factory/` — never next to the baseline.**
3. Run it (Step 2 shape, into `audit-runs/<DATE>/<id>__v2.jsonl`) and judge it
   (Step 3) with the baseline's `payoff_axis`.
4. Record the candidate result with `candidate_of: "<baseline id>"` so the
   journal computes the A/B delta vs the same-run baseline (`vs base +N ✅`
   when it wins).

A candidate that beats its baseline is a *promotion suggestion*, not a
promotion — it stays in `improvements/`. See § Promotion.

## Step 5 — Append the journal

1. Compose the results JSON (schema in `append_audit.py`'s docstring: date /
   model / notes / per-scenario id, name, channel, category, yaml, run_log,
   status, attempts, duration_sec, scores {coherence, interaction,
   breakdown_free, payoff}, payoff_axis, comment, error, candidate_of). Write
   it to a temp file.
2. ```bash
   python3 .claude/skills/scenario-refine/scripts/append_audit.py \
     --results /tmp/refine_results_<DATE>.json \
     --journal data/factory/audit-digest.md
   ```
3. Verify: `grep -c 'audit-digest:' data/factory/audit-digest.md` prints `2`
   (both markers survived) and the new `## <DATE>` section exists.

## Step 6 — Report

Summarize for the user: per-scenario status + scores, **regressions (`⚠️`)
called out first**, A/B candidate wins (`vs base +N ✅`) with where the YAML
lives, failures with one-line causes, and where the artifacts are
(`audit-runs/<DATE>/`, `improvements/<DATE>/`, the appended journal section).
The journal is a gitignored local log — not committed or pushed. Only
*promoting* a winner (§ Promotion) goes through `/orchestrate`.

## Promotion

The journal and A/B candidates are never auto-promoted. To act on a winning
result, pick a channel by reach and commit via an `/orchestrate` PR:

- **Bundled preset** (ships in the app binary): copy the winning YAML (the
  baseline being *replaced*, or a polished `__v2` from `improvements/`) into
  `Pastura/Pastura/Resources/Presets/`, renaming `id:` back to the canonical
  preset id. Routes through the blocklist pre-commit gate; reaches users only
  on the next TestFlight / App Store build (so a preset swap also needs
  `/release`).
- **Shared-scenario gallery** (remote — served from `main` via
  `raw.githubusercontent.com`, so **merge is the deploy**): copy to
  `docs/gallery/<slug>_vN.yaml`, bump the `id:`/version, then run
  `scripts/add-gallery-entry.sh`. The gallery does NOT pass the blocklist gate
  — curate by the judge scores yourself. Full bridge:
  `docs/gallery/README.md` § "Promoting from the scenario factory".

Both paths are deliberate human steps so a low-coherence or unsafe candidate
can never auto-ship.

## Scheduling (how the unattended run works)

- **The skill never self-registers** (see Non-goals). Scheduling is an
  operator action: a **Claude Desktop *local* Routine** drives the cycle.
  Cloud routines are unusable — generation + judging + harness inference need
  the local llama.cpp + GGUF, which a cloud clone can't reach.
- **The journal is a gitignored local log — never committed or pushed.** Each
  run appends a section in place (date-idempotent); no rolling PR, no branch
  state. A *manual* `/scenario-refine` behaves identically.
- **Run in the user's main checkout — not a throwaway worktree.** The
  gitignored journal + `audit-runs/` + `improvements/` must persist between
  nights so Step 1's rotation reads the full history; a fresh per-run worktree
  would lose it.
- **Routine recipe** (Desktop → Routines → New routine):
  - **Type**: Local
  - **Name**: `scenario-refine-nightly`
  - **Working folder**: the user's main checkout (`/Users/tyabu12/Work/pastura`)
  - **worktree toggle**: **OFF** (must run in the persistent main checkout)
  - **Schedule**: any slot where the machine is awake + idle + on AC and that
    does not overlap another family routine (queue-consumer 1:30,
    scenario-factory's slot). The cycle is time-agnostic; same-day re-runs
    replace that date's section.
  - **Permission mode**: **`acceptEdits`** (not `bypassPermissions`) —
    auto-accepts the in-session writes (v2 candidate YAMLs under
    `data/factory/improvements/`); least-privilege. The safety boundary (only
    `data/factory/` is written) is what makes `acceptEdits` safe here.
  - **Instructions**: `Run the /scenario-refine skill for tonight's cycle.`
- **No settings.json change.** The skill writes only gitignored local files
  and makes no `git push` / `gh` calls, so no allowlist additions are needed.
- **Environment prerequisites**: AC power, machine awake (non-sleep), idle at
  fire time — the cycle burns local GGUF inference.
