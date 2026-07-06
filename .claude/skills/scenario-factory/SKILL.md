---
name: scenario-factory
description: Run one scenario-factory cycle — generate 3 fresh scenario YAMLs, execute each on pastura-harness with real local-LLM inference, judge the transcripts in-session, and append the local digest. Use when the user asks to run the scenario factory, run a factory cycle, generate and field-test new scenarios, or dogfood scenarios overnight.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# /scenario-factory

One full factory cycle: **generate → run → judge → digest** (ADR-013
Phase 2, #521). Run from the repository root.

Non-goals:

- **No scheduled execution.** This skill never registers itself as a
  Routine / cron — invocation is manual or via a Phase 3 routine that
  calls it.
- **No content-safety screening.** The judge scores quality only; safety
  is enforced by the blocklist pre-commit gate when a scenario is later
  promoted to a **bundled preset** under `Resources/Presets/`. The
  **shared-scenario gallery** channel (`docs/gallery/`) does NOT pass
  through that gate — curate gallery content by hand. Both channels: see
  § Promotion below.
- **No external LLM APIs.** Generation and judging are done by THIS
  session. Only the local harness (llama.cpp + bundled GGUF) burns
  inference.

## Constants

- `MODEL`: `~/Models/gemma-4-E2B-it-Q4_K_M.gguf` (sha256 matches the
  `ModelRegistry` pin)
- `DATE`: today as `YYYY-MM-DD`; `DATESTAMP`: `YYYYMMDD`
- Generated YAMLs: `data/factory/scenarios/<DATE>/` (gitignored; kept
  local for later promotion — do NOT write into `runs/`, that is the
  harness output dir)
- Run logs: `data/factory/runs/<DATE>/<id>.jsonl` (gitignored; harness
  stderr lands in a `.stderr.log` sidecar next to each log)
- Digest: `data/factory/digest.md` (gitignored local log — appended in
  place, never committed; bootstrapped by `append_digest.py` if absent)
- Per-run timeout: `600` seconds (not the harness default 1800 — bounds a
  wedged run at 2 attempts × 600 s)
- Helper scripts: `.claude/skills/scenario-factory/scripts/` (incl.
  `gallery_census.py` — the Step 1.5 novelty census)

## Step 0 — Preflight

1. `ls ~/Models/gemma-4-E2B-it-Q4_K_M.gguf` — abort with a clear message
   if the model is missing.
2. `command -v jq` — required by the run wrapper.
3. `swift build` once to warm the harness build (incremental afterwards).
   A build failure aborts the cycle — report it, do not generate.

## Step 1 — Read prior scenarios (dedup)

Read `data/factory/digest.md`. Collect every past scenario **id, name,
theme, and comment** from the section tables. The new batch must not
repeat: same premise, same persona cast, or a theme judged ≤2 on humor
twice in a row. Low-scoring past entries are signals about what NOT to
generate again; high scorers indicate directions worth varying further.

Also collect the **`name` + `description`** of every already-shipped
scenario, so generation can avoid colliding with the inventory it might
later be promoted into (§ Promotion):

- Bundled presets — `Pastura/Pastura/Resources/Presets/*.yaml`, **excluding
  the `*_en.yaml` English mirrors** (they duplicate the `ja` originals).
- Shared-scenario gallery — `docs/gallery/*_v1.yaml` (read only the YAML
  `name:` / `description:` scalars; skip `README.md` / `gallery.json` /
  `shared-scenario-reports.md`).

A new scenario that repeats a shipped preset/gallery premise, mechanics, or
persona cast is a dedup miss even when the digest is clean.

## Step 1.5 — Pick under-represented axes (novelty census)

The gallery has skewed toward a `vote → score_calc → summarize` scoring
spine (most entries share it) and `category: creative` — without a counter-
force, every batch piles onto the crowded majority. Steer **toward the gaps**:

```bash
python3 .claude/skills/scenario-factory/scripts/gallery_census.py
```

The census is **deterministic and gallery-only** — it counts phase-*type*
presence (does a scenario contain a `vote` phase at all?), not mechanical
depth, and ranks 10 structural mechanic axes + the 6 categories by rarity.
Read its `Suggested targets` block and **assign each of the 3 scenarios a
DISTINCT under-represented axis** (a mechanic axis, a category, or both),
avoiding the `crowded` ones. Valid categories: `social_psychology`,
`game_theory`, `ethics`, `roleplay`, `creative`, `experimental` — the
zero-entry ones (`game_theory` / `experimental`) are the rarest possible.

Cross-night rotation is an **in-session reasoning step**, not the script:
scan the digest's recent `axis` column (Step 5) and, if a suggested axis was
already targeted in the last 1–2 nights but is **not yet promoted** to the
gallery, rotate to the next gap so the same hole isn't refilled before
promotion catches up.

The census also prints a `⚠️ NEW ENGINE MECHANICS not yet in the census axes`
warning when `PhaseType` gains a phase no axis covers (the auto-follow
tripwire). When it fires, treat the listed phase(s) as the **TOP-priority** axis
assignment for the batch — they are by definition 0-represented. BEFORE
authoring with an unfamiliar phase, read
`Pastura/Pastura/Engine/Phases/<X>Handler.swift` (its header docs give the
semantics, output-field contract, and cost) and tracking issue #906 (the
interestingness umbrella — design considerations for every recent / planned
phase).

## Step 2 — Generate 3 scenario YAMLs

Write 3 files to `data/factory/scenarios/<DATE>/<id>.yaml` with
`id: factory_<DATESTAMP>_<slug>` (snake_case slug, also the filename).

Theme: **driven by the per-scenario axis from Step 1.5**, not a fixed
focus. The oogiri / comedy family is a strong default *tone* — use
`Pastura/Pastura/Resources/Presets/bokete.yaml` as the schema/tone
reference — but the assigned mechanic axis dictates the *format* (e.g.
`elimination` → knockout bracket, `branching` → `conditional` divergent
paths, `reactive_event` → `event_inject`, `scoring_free` → observation /
discussion with no vote), and an assigned **category** axis may rotate the
premise out of comedy entirely (a `game_theory` cooperation dilemma, an
`experimental` social-psych setup à la the original asch/trolley seeds). A
non-comedy scenario is judged on its own terms — see Step 4. Each of the 3
must differ from the other 2 AND from digest history in premise or
mechanics, not merely in topic strings.

Schema requirements (ScenarioLoader — all required):

- `id`, `name`, `description`, `language: ja`, `agents`, `rounds`,
  `context`, `personas` (name + description each; count == `agents`),
  `phases`
- Agents 2–10, rounds ≤ 30. Personas need distinct comedic stances
  (the bokete preset's 【立場】/【目的】+ example-line format works well).
- LLM phases (`speak_all` / `speak_each` / `vote` / `choose`) need
  `prompt` + `output` field maps; `vote` needs `exclude_self` thought
  through; scoring usually wants a `score_calc` (logic: `vote_tally`)
  and a `summarize`.
- **Canonical `output` field names** (enforced by
  `ScenarioValidator.validateForCommit`): primary = `statement` (speak),
  `action` (choose), `vote` (vote). The optional private-thought field is
  `reason` for `vote`, `inner_thought` for `speak_all` / `speak_each` /
  `choose`. Do NOT author `reason` on a choose/speak phase — it streams live
  but goes blank on the committed row, and the commit gate rejects it (#760).
- `reflect` (per-agent private memo, #907) — output field `note` (canonical,
  required; no secondary thought field). The memo is stored under the reserved
  `notes_<name>` namespace and re-injected into that agent's OWN later prompts
  only (system-prompt section + `{my_notes}`) — never into the shared
  conversation log. NOT allowed inside a `conditional` branch. Inference cost =
  agents per round. Reference preset:
  `Pastura/Pastura/Resources/Presets/word_wolf.yaml`.
- `whisper` (pair-private conversation, #908) — `prompt` optional (a
  language-aware default exists); phase-level `rounds:` optional (default 1;
  the same key speak_each uses — it maps to sub_rounds, the exchanges per
  pair). Output: `statement` (canonical primary, required) + optional
  `inner_thought`. Active agents pair off in persona order, rotated per round
  (an odd agent sits out); exchanges NEVER enter the shared conversation log —
  viewers see them (dramatic irony), other agents don't. Each participant's
  latest exchange is surfaced back only to them via the reserved
  `whispers_<name>` key (overwrite — latest only) + `{my_whispers}`. NOT
  allowed inside a `conditional` branch. Inference cost =
  (agents ÷ 2) × sub_rounds × 2 (integer division; odd agent sits out).
- `log_window: N` (scenario-level top-level key, int ≥ 1, #907) — trims the
  conversation log passed to PROMPTS to the last N entries; persistence, replay,
  and export keep the full log. This is the **information-asymmetry lever**: it is
  the retry lever for the 2026-07-06 digest lesson that a telephone-game decay
  experiment needs predecessor-only visibility (`log_window: 1` approximates it).
- Plain YAML only — no markdown fences in the file.

Inference budget — compute BEFORE writing each file:

```
per round: speak_all = agents | speak_each = agents × sub_rounds
           vote = agents     | choose = agents × 2 (round_robin) / agents
           reflect = agents  | whisper = (agents/2) × sub_rounds × 2
           code phases (assign / score_calc / eliminate / summarize /
           event_inject) = 0 | conditional = max(then, else)
total = per-round sum × rounds   →  target ≤ 50 (hard block > 100)
```

A bokete-shaped scenario (5 agents, 2 rounds, speak_all + vote) costs 20
and runs ≈ 4 min; keep the whole batch ≤ ~120 total so the cycle fits the
night budget even with retries.

## Step 3 — Run each scenario on the harness

Sequentially (one model in RAM at a time), for each generated YAML:

```bash
bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
  data/factory/scenarios/<DATE>/<id>.yaml \
  ~/Models/gemma-4-E2B-it-Q4_K_M.gguf \
  data/factory/runs/<DATE>/<id>.jsonl 600
```

The wrapper prints one JSON status line (`status`: `ok` / `failed` /
`config_error`) and **always exits 0** — parse the line, record it, and
move to the next scenario regardless of outcome. Crash tolerance is the
contract (#253: a known llama.cpp SIGABRT kills a fraction of runs;
events up to the crash survive in the JSONL):

- `failed` → keep the partial JSONL + `.stderr.log` for diagnosis; do NOT
  retry in-cycle (the harness already retried once internally).
- `config_error` → the generated YAML itself is broken (schema or >100
  inference estimate). Fix the YAML once and re-run that scenario once;
  if it config-errors again, record and move on.

Use a generous Bash timeout (≥ 900 000 ms) or `run_in_background` per
run; expect ~4–10 min each.

## Step 4 — Judge in-session

For each run with `status == ok`:

```bash
python3 .claude/skills/scenario-factory/scripts/format_transcript.py \
  data/factory/runs/<DATE>/<id>.jsonl
```

Read the transcript and score the rubric — each axis 1–5 plus a one-line
comment per scenario:

| Axis | What 5 looks like | What 1 looks like |
|---|---|---|
| (a) coherence | Outputs consistently honor premise & personas | Agents ignore the setting |
| (b) interaction | Agents react to each other; votes track content | Parallel monologues |
| (c) breakdown_free | No format breaks, language drift, or nonsense loops | Frequent breakdowns |
| (d) humor | Genuinely funny lines a human would quote | Flat or incoherent |
| (e) development | The situation, relationships, or choices genuinely move across rounds; late rounds couldn't be predicted from round 1 | Each round replays round 1 (one-note gimmick repetition) |

**Development (e) is UNIVERSAL** — score it for *every* scenario (unlike humor,
which is category-gated below), on the same 1–5 scale. `null` is allowed only
for a single-round scenario (nothing can develop across one round; the digest
renders `–`). In this skill development is column **(e) after humor**; the
sibling `/scenario-refine` journal renders it as **(d) before payoff** — the
axes are keyed by NAME (`development`), not by letter, so the two orders are
intentionally different.

**Category-aware (d):** humor is the right axis for a comedy-family
scenario, but a scenario whose Step 1.5 axis rotated to a non-`creative`
category (`game_theory` / `experimental` / `social_psychology` / `ethics`)
should NOT be penalized for not being funny — that would teach the loop to
avoid the diversity the census requested. For those, score (d) `null` (the
digest renders `–`) and judge the scenario on (a)–(c) + (e) development plus
whether it delivers its category's intended payoff (a real dilemma, a
believable experiment). Note this in the comment.

Failed runs get **no scores** — record the status and the wrapper's
`error` (skim the partial transcript only to classify the failure for
the comment). The judge is a quality filter, not a safety screen.

## Step 5 — Append the digest

1. Write the results JSON (schema documented in `append_digest.py`'s
   docstring: date / model / notes / per-scenario id, name, theme, **axis**,
   yaml, run_log, status, attempts, duration_sec, scores (5 axes: coherence /
   interaction / breakdown_free / humor / development), comment, error) to
   a temp file. Set `axis` to the Step 1.5 axis this scenario targeted (e.g.
   `"elimination / creative"`) so cross-night rotation can read it back.
2. ```bash
   python3 .claude/skills/scenario-factory/scripts/append_digest.py \
     --results /tmp/factory_results_<DATE>.json \
     --digest data/factory/digest.md
   ```
3. Verify: `grep -c 'factory-digest:' data/factory/digest.md` must print
   `2` (both markers survived), and the new `## <DATE>` section exists.

## Step 6 — Report

Summarize for the user: per-scenario status + scores + best line of the
night, failures with one-line causes, and where the artifacts live
(`scenarios/<DATE>/`, `runs/<DATE>/`, the appended digest section).
`data/factory/digest.md` is a gitignored local log — the new section is
appended in place and is NOT committed or pushed. Only *promoting* a
winning scenario (bundled preset or shared-scenario gallery; see
§ Promotion) goes through the normal `/orchestrate` flow.

## Promotion

The digest itself is never promoted — it is a local judging journal. To
ship a winning scenario, pick a distribution channel by reach and commit
via an `/orchestrate` PR either way:

- **Bundled preset** (ships in the app binary): copy the winning YAML from
  `data/factory/scenarios/<date>/` to `Pastura/Pastura/Resources/Presets/`.
  Landing under `Resources/` routes it through the blocklist pre-commit
  gate; reaches users only on the next TestFlight / App Store build.
- **Shared-scenario gallery** (remote — served from `main` via
  `raw.githubusercontent.com`, so **merge is the deploy**): copy to
  `docs/gallery/<slug>_v1.yaml` (rename the YAML's `id:` from
  `factory_<date>_<slug>` to `<slug>_v1`), then run
  `scripts/add-gallery-entry.sh`. The gallery does **not** pass through the
  blocklist gate — curate by the judge scores yourself (hold back
  low-coherence / low-humor runs). Full bridge: `docs/gallery/README.md`
  § "Promoting from the scenario factory".

## Scheduling (how the unattended run works)

- **The skill never self-registers** (see Non-goals "No scheduled
  execution"). Scheduling is an operator action: a **Claude Desktop
  *local* Routine** drives the cycle (see the recipe below). Cloud
  routines are unusable here — generation + judging burn the llama.cpp +
  GGUF harness, which a cloud clone can't reach.
- **The digest is a gitignored local log — never committed or pushed.**
  Each night appends a section in place; there is no rolling PR and no
  branch state. `append_digest.py` bootstraps the file if it is absent.
  A *manual* `/scenario-factory` behaves identically. (Promoting a winning
  scenario is a separate `/orchestrate` PR — see § Promotion.)
- **Run in the user's main checkout — not a throwaway worktree.** The
  gitignored digest, `scenarios/<DATE>/`, and `runs/<DATE>/` must persist
  between nights so Step 1 dedup reads the full history; a fresh per-run
  worktree would start with an empty bootstrapped digest and lose that
  history. The digest being gitignored is what keeps the main working tree
  clean despite running there.
- **Routine recipe** (Desktop → Routines → New routine):
  - **Type**: Local
  - **Name**: `scenario-factory-nightly`
  - **Working folder**: the user's main checkout (`/Users/tyabu12/Work/pastura`)
  - **worktree toggle**: **OFF** (must run in the persistent main checkout)
  - **Schedule**: any slot works as long as the machine is awake + idle + on
    AC and it does not overlap another family routine (queue-consumer is
    1:30). The cycle is time-agnostic; same-day re-runs replace that date's
    section (date-idempotent append).
  - **Permission mode**: **`acceptEdits`** (not `bypassPermissions`) —
    auto-accepts in-session file writes (generated YAMLs); least-privilege.
  - **Instructions**: `Run the /scenario-factory skill for tonight's cycle.`
- **No settings.json change.** The skill writes only gitignored local files
  (digest, scenarios, runs) and makes no `git push` / `gh` calls, so no
  allowlist additions are needed.
- **Environment prerequisites**: AC power, the machine awake (non-sleep),
  and idle at fire time — the cycle burns local GGUF inference.
