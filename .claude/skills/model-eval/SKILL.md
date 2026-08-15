---
name: model-eval
description: Run one Mac-side model evaluation battery cycle — drive a candidate GGUF through the 6-cell scenario battery on pastura-harness with real local-LLM inference, score each transcript against the scenario-refine rubric, and append the local eval digest. Use when the user asks to run a model eval, evaluate a candidate model, run the model battery, compare a new GGUF model, or モデル検証・モデル評価.
allowed-tools: Read, Write, Grep, Glob, Bash
---

# /model-eval

One full battery cycle: **preflight → run (6 cells) → metrics → judge →
verdict → scorecard**. Stage 2 of the model validation & onboarding pipeline
(#975; Stage 1 = the harness `--profile` plumbing, PR #970). Run from the
repository root.

Args (both **required**):

- `<gguf-path>` — absolute path to the candidate GGUF file.
- `<profile-id>` — a `ModelProfile.all` id. Today: `gemma-4-e2b-q4-k-m` or
  `qwen-3-4b-q4-k-m`.

## Positioning (read first — load-bearing)

This skill is the cheap Mac-side **filter gate (足切り)**. It can **REJECT** an
obviously unfit candidate cheaply — but it can **NOT accept**. A battery pass
only *advances* a candidate to the real accept gate: the on-device GBNF PoC
under **ADR-011's five prerequisites** — P1 non-gated GGUF source, P2 CONTROL
token flags, P3 on-device GBNF PoC on ≥ 2 presets, P4 no catalog regression,
P5 no raw prompt-token sampler accept. **A Mac-battery pass MUST NEVER be
reported as "adopted".** Say "passes the Mac filter — advance to the ADR-011
real-device PoC", never "adopt this model".

**Rubric inversion.** This reuses the `/scenario-refine` rubric, but here the
scenarios are FIXED known-good shipped presets, so the judgment is inverted: a
low score indicts the **model**, not the scenario. The battery presets are the
control; the model is the variable.

**New model family needs a Stage-0 profile PR first.** `<profile-id>` MUST
already exist in `ModelProfile.all`. A candidate from a family not yet
registered (neither gemma nor qwen) requires a prior `tools/harness` PR adding
the `ModelProfile` static + its pin test (PR #970's pattern) BEFORE this skill
runs — otherwise every cell 6× `config_error`s on the unknown profile. Do not
invoke with an unregistered id; land the profile PR through `/orchestrate`
first.

## Safety boundary (read first)

**This skill writes ONLY under `data/models/`** — the raw run logs
(`eval-runs/`) and the scorecard journal (`eval-digest.md`), both gitignored.
It MUST NEVER edit `Pastura/Pastura/Resources/Presets/` (its read-only battery
input), the gallery, or any app code. It makes no `git` commit and no
`git push` / `gh` call, so even an errant write stays a dirty working tree and
can never reach users. `allowed-tools` omits `Edit` — the only writes are new
JSONL run logs, a temp `results.json`, and the appended journal.

## Non-goals

- **No model adoption.** See Positioning — this gate cannot accept; adoption is
  the human-driven ADR-011 real-device PoC.
- **No preset edits / no profile authoring.** The battery presets are read-only
  controls; registering a new `ModelProfile` is a separate `tools/harness` PR
  (Stage 0), never done by this skill.
- **No external LLM APIs.** Judging is done by THIS session; only the local
  harness (llama.cpp + the candidate GGUF) burns inference.
- **No scheduled execution self-registration.** Model evaluation is operator-
  initiated, on demand per candidate.

## Constants

- `GGUF`: the `<gguf-path>` arg. `PROFILE`: the `<profile-id>` arg.
- `DATE`: today as `YYYY-MM-DD`.
- Battery: the 3 preset families × {ja, en} = **6 cells**:

  | family | ja preset | en preset | category | `payoff_axis` |
  |---|---|---|---|---|
  | word_wolf | `word_wolf.yaml` | `word_wolf_en.yaml` | game_theory | `strategic_tension` |
  | prisoners_dilemma | `prisoners_dilemma.yaml` | `prisoners_dilemma_en.yaml` | game_theory | `strategic_tension` |
  | bokete | `bokete.yaml` | `bokete_en.yaml` | creative | `humor` |

  All under `Pastura/Pastura/Resources/Presets/`. The category → `payoff_axis`
  mapping is derived from `/scenario-refine`'s `select_inventory.py`
  (`PRESET_CATEGORY` + `CATEGORY_AXIS`) — pin these values so the judge scores
  the same 5th axis the refine journal would.
- Run logs: `data/models/eval-runs/<DATE>/<family>_<lang>.jsonl` (gitignored;
  harness stderr lands in a `.stderr.log` sidecar).
- Journal: `data/models/eval-digest.md` (gitignored local scorecard log —
  appended in place, never committed; bootstrapped by `append_eval.py`).
- Per-run timeout: `600` seconds (positional — required to reach the 5th
  `profile_id` arg of `run_scenario.sh`).
- Helper scripts: `.claude/skills/model-eval/scripts/` (this skill:
  `analyze_model_eval.py`, `append_eval.py`) plus **two shared scripts borrowed
  from the factory** (not duplicated): `run_scenario.sh` and
  `format_transcript.py` under `.claude/skills/scenario-factory/scripts/`. A
  factory refactor that moves/renames those breaks this skill (Step 0 checks).

## Step 0 — Preflight (fail fast, before any run)

1. `ls <gguf-path>` — abort with a clear message if the GGUF file is missing.
2. `grep -F 'id: "<profile-id>"' tools/harness/Sources/PasturaHarnessKit/ModelProfile.swift`
   — abort if the profile id is not registered in `ModelProfile.all` (see
   Positioning: a new family needs a Stage-0 profile PR first).
3. `command -v jq` — required by the run wrapper and the helper scripts.
4. `ls .claude/skills/scenario-factory/scripts/run_scenario.sh .claude/skills/scenario-factory/scripts/format_transcript.py`
   — abort if the borrowed factory scripts are gone (cross-skill dependency).
5. `ls` all 6 battery preset paths (table above) — abort if any is missing
   (guards a future preset rename).
6. `swift build` once to warm the harness build (incremental afterwards, so the
   per-run builds inside `run_scenario.sh` are no-ops). A build failure aborts
   the cycle — report it, do not run.

## Step 1 — Run the 6-cell battery (foreground, sequential)

Run the cells **one at a time, in the foreground** — one model in RAM at a
time. For each battery cell, from the repo root:

```bash
bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
  Pastura/Pastura/Resources/Presets/<preset> \
  <gguf-path> \
  data/models/eval-runs/<DATE>/<family>_<lang>.jsonl \
  600 \
  <profile-id>
```

The wrapper prints one JSON status line (`status`: `ok` / `failed` /
`config_error`) and always exits 0 — parse it, record it, move on. Use a Bash
tool `timeout` of ~`660000` ms per run (one run ≈ 150–400 s).

**NEVER background these runs and poke them mid-run.** The background-poke kill
trap orphans the harness process (kills llama.cpp mid-load, corrupts the
JSONL). Foreground-sequential only.

A `failed` / `config_error` cell does **NOT** abort the battery: record its
status, continue to the next cell. It gets NO rubric scores (rendered `–` in
the journal). A `config_error` here is a real model↔profile signal — the
harness rejected the run before inference (e.g. a profile mismatch); record it
as a non-`ok` row.

## Step 2 — Aggregate metrics

After ALL 6 cells finish, run the analyzer once over every JSONL produced:

```bash
python3 .claude/skills/model-eval/scripts/analyze_model_eval.py \
  data/models/eval-runs/<DATE>/*.jsonl
```

It emits one JSON object: per-run `status` / `attempts` / `tok_per_sec` /
`language_mismatches`, plus an `aggregate` with `runs_ok`, `runs_failed`,
`language_mismatch_total`, `attempts_mean`, `tok_per_sec_overall`. Note:
`attempts` (1 first-try, 2 after the Engine retry) is the **only** retry proxy
— JSON-repair diagnostics never reach the JSONL. `aggregate.runs_total` counts
only cells that produced a log file (a `config_error` before first write leaves
none) — battery completeness comes from the 6 wrapper status lines, not from
`runs_total == 6`. Read this object; it feeds the scorecard's per-cell metrics
and the verdict.

Then sweep the **stderr sidecars** for the sampler markers. The analyzer reads
the JSONL only, and none of these reach it:

```bash
grep -oE 'samplerDrySeeded|samplerDryUnavailable reason=[a-z-]+|samplerGrammarResample|samplerMaskedSelection|samplerCrashCaught' \
  data/models/eval-runs/<DATE>/*.stderr.log | sort | uniq -c
```

Read the DRY markers (#1483) **against the cell's phase shape**, never as a
bare count — `speak_each` is the only phase in Engine that seeds DRY, and only
from its second round on:

| observation | reading |
|---|---|
| `samplerDrySeeded` in `word_wolf` ja/en | expected — the only battery cells with a `speak_each` phase |
| `samplerDrySeeded` **zero** in `prisoners_dilemma` / `bokete` | **correct, not a defect.** Neither preset has a `speak_each` phase, so 4 of the 6 cells emit only `reason=no-seeds` |
| `reason=disabled` in a plain battery | DRY is off — `PASTURA_DRY_MULTIPLIER` leaked into the environment; the arm is invalid, re-run |
| `reason=null-init` or `reason=no-model` | never expected; either is a defect worth an issue |
| fewer markers than the cell's generations | a **throwing** exit — grammar parse failure (#194) or grammar-without-vocab — which emits no marker and whose own error goes to OSLog only, so the sidecar shows neither. Check `run_end.status` / `attempts`, not the sweep alone |
| **no `samplerDry*` line at all** | the one unambiguous instrument failure — every non-throwing `createSampler` exit emits exactly one |

**Do not reconcile the `samplerDry*` total against `inference_completed`** —
the two count different things and drift in *both* directions. `narrate` hands
`LLMCaller` a no-op emitter, so its inference emits no events and pushes markers
**up**; a generation that throws at or before sampler construction pushes them
**down**. Retries do not enter: `emitInferenceCompleted` sits inside
`LLMCaller`'s `for attempt` loop on both the success and failure paths, so an
extra attempt increments both sides. Measured on `word_wolf` ja at the b8694
pin, in both A/B arms: 26 markers vs 25 `inference_completed`, the difference
being that one narrate turn (`docs/models/eval-log.md` § "DRY sampler
construction").

## Step 3 — Judge each `ok` cell in-session

For each cell with `status == ok`:

```bash
python3 .claude/skills/scenario-factory/scripts/format_transcript.py \
  data/models/eval-runs/<DATE>/<family>_<lang>.jsonl
```

Read the transcript and score the 5 `/scenario-refine` axes, each 1–5 plus a
one-line comment. Axes (a)–(d) are universal; (e) `payoff` is the family's
`payoff_axis` from the Constants table:

| Axis (key) | What 5 looks like |
|---|---|
| (a) `coherence` | Outputs consistently honor premise & personas |
| (b) `interaction` | Agents react to each other; votes track content |
| (c) `breakdown_free` | No format breaks, language drift, or nonsense loops |
| (d) `development` | The situation/choices genuinely move across rounds |
| (e) `payoff` | `strategic_tension`: strategies diverge, real push-and-pull. `humor`: genuinely funny lines a human would quote |

Store scores under the fixed key `payoff` (the axis *name* travels in
`payoff_axis`). Failed / config_error cells get NO scores (`rubric: null`).

After all `ok` cells are scored, write the model-level qualitative field
**`differentiation`**: how this model's outputs differ in character from the
current catalog (Gemma 4 E2B, Qwen 3 4B). This is the slot-earning judgment —
the catalog stays curated at 3–5 models, each earning its slot by *distinct
character*, not marginal score; a model that merely duplicates an incumbent's
character earns no slot even with decent scores.

## Step 4 — Verdict (asymmetric, variance-aware)

Gate ∈ `pass` | `borderline` | `fail` | `blocked`. **Mechanical prerequisites
for `pass`** (all required): all 6 cells `ok` AND `language_mismatch_total == 0`
AND no `crashed` cell. Beyond the mechanical floor, weigh the rubric totals and
`differentiation` against the eval-digest history / incumbent baseline — do NOT
pin numeric tok/s or rubric-total thresholds (mechanism-contract style; the
`<!-- eval-data: ... -->` comments in prior sections are parseable for the
comparison).

- **Clear pass / clear fail** — decisive; record it.
- **BORDERLINE aggregate** (e.g. one `failed` cell, or a weak rubric on 1–2
  cells) → recommend **RE-RUNNING the weak cell(s)** before any reject.
  Single-run-per-cell means one unlucky sample must not discard a candidate;
  the reject bar is asymmetric — cheap to re-sample, expensive to wrongly
  discard. Re-run into the same `<family>_<lang>.jsonl` path and re-judge.
- **BLOCKED** — the candidate could not be *evaluated*, so there is nothing to
  reject. Non-terminal by definition: it is retry-gated, not an endpoint.

### `blocked` — admissibility and its two enforcement layers

`fail` says "measured, and it isn't good enough"; `blocked` says "not measured".
Choosing between them is an **attribution** judgment — did the non-`ok` cells
fail because of the candidate, or because of the environment? — and that is NOT
derivable from cell statuses, so most of it cannot be mechanised.

**Admissibility (prose — no code executes this; it is your call):** `blocked` is
admissible only when **every non-`ok` cell shares one failure CAUSE that is
independent of scenario content** — a model-load error, a runtime/toolchain
incompatibility, a known infra path — rather than a per-scenario quality
breakdown.

**Cause, not incidence.** A scenario-independent cause can still have
scenario-*correlated* incidence. Sarashina 2.2 3B on 2026-07-08 failed only the
longer, reflect-heavy cells while short ones completed — which looks
scenario-shaped — but the cause was the #751 empty-output retry-budget path, and
fixing that one upstream defect cleared every cell (PR #1024). **The tell is
exactly that**: if one upstream fix would clear all of them, the cause is
independent of scenario content however its incidence distributed. If instead
each cell fails for its own scenario-shaped reason, that is `fail` or
`borderline`.

Do not reach for `blocked` to soften a genuine quality reject; the whole value
of the token is that a future reader can trust it means "unmeasured". Nothing
downstream re-checks that — the required `retry` pointer is the only backstop,
and it works only when someone actually runs the retry. A mechanical proxy
("all non-`ok` cells share one error signature") was considered and rejected:
the run artifacts *do* carry per-cell error text, so the proxy is constructible
— but that text is session-authored, so identity across cells is self-attested,
and it would catch sloppiness rather than misuse.

**Structure (enforced by `append_eval.py`; it exits 1 otherwise):**

| Rule | Why |
|---|---|
| `verdict.unblocked_by` required, non-empty | A blocked entry without a named unblock condition is a `fail` with softer wording |
| `verdict.retry` required, non-empty | The retry pointer is what makes it non-terminal. The blocker's own issue number is acceptable — a dedicated retry issue need not exist yet |
| **no** `differentiation` when zero cells are `ok` | Zero inferences means zero evidence; a value here would be fabricated |
| `differentiation` **required** when ≥1 cell is `ok` | A partial block still measured something — record what the completed cells showed, scoped to them. Declining is legitimate; see below |
| at least one non-`ok` cell | *Coherence assert only* — it rejects a battery whose every row is `ok`, i.e. a self-contradictory composition. It does **not** distinguish `blocked` from `fail` (a `fail` has non-`ok` cells too), and it is satisfiable by recording only the failing rows, since nothing checks the battery for completeness. Do not read it as a substantive guard |

**Declining a partial differentiation is legitimate.** The validator checks only
that the field is non-empty, so `PARTIAL (n/6 cells) — insufficient to
differentiate` satisfies it. Use that form rather than stretching one or two
completed cells into a slot-earning judgment. The required-when-partial rule
exists so real evidence is not silently discarded, not to manufacture a verdict
— the same fabrication pressure the zero-`ok` rule guards against, arriving from
the other side.

Note the two `differentiation` rows: a blocked run is **not** necessarily a
total block. The worked precedent (Sarashina 2.2 3B, 2026-07-08 — 3 of 6 cells
hard-failed, so some completed) is in `docs/models/eval-log.md` under the
2026-07-23 entry's *Grandfathered (#1419)* sub-bullet.

## Step 5 — Append the scorecard

1. Compose the results JSON (schema in `append_eval.py`'s docstring: `date`;
   `model` `{profile_id: "<profile-id>", gguf: "<gguf-filename-stem>"}`;
   `battery[]` per cell with `scenario_id`, `language`, `status`, `attempts`,
   `language_mismatches`, `tok_per_sec`, `rubric` (the 5 axes + `payoff_axis`,
   or `null` for failed/config_error cells), `comment`; `differentiation`;
   `verdict` `{gate, notes}` — plus `{unblocked_by, retry}` when the gate is
   `blocked`, and see Step 4 for when `differentiation` must be omitted).
   Write it to a temp file (`mktemp` or the session scratchpad — not inside
   the repo).
2. ```bash
   python3 .claude/skills/model-eval/scripts/append_eval.py \
     --results <tmp>/results.json \
     --journal data/models/eval-digest.md
   ```
   The section key is `(date, profile_id)` — a same-day re-run for the same
   profile REPLACES that section (idempotent), leaving other profiles' sections
   for that date untouched.
3. Verify: `grep -F '## <DATE> — <profile-id>' data/models/eval-digest.md`
   prints the new heading.

## Step 6 — Report

Compact final report to the user:

- **Per-cell table**: family, lang, status, attempts, lang-mismatch, tok/s, the
  5 axis scores + total (failed cells show `–`).
- **Aggregate metrics** (Step 2): `runs_ok` / `runs_failed`,
  `language_mismatch_total`, `attempts_mean`, `tok_per_sec_overall`.
- **Differentiation**: the one-paragraph slot-earning judgment. For a `blocked`
  run with zero `ok` cells, report it as **UNASSESSABLE** and say why — do not
  improvise a judgment from zero inferences.
- **Gate** (`pass` / `borderline` / `fail` / `blocked`) with the explicit line
  that a **pass only advances the candidate to the ADR-011 real-device GBNF
  PoC** — it is not an adoption. For `blocked`, state the unblock condition and
  the retry pointer, and say plainly that the candidate was **not rejected**.
- Artifact locations (`data/models/eval-runs/<DATE>/`, the appended
  `eval-digest.md` section) — a gitignored local log, not committed or pushed.

## Self-test

`.claude/skills/model-eval/tests/run_tests.sh` exercises the two helper scripts
(analyzer + appender) and `run_scenario.sh`'s `--profile` argv passthrough
against fixtures (no Swift toolchain, no model — `PASTURA_HARNESS_BIN` fakes the
harness). It is wired into CI via the shim
`scripts/tests/model-eval-test.sh` (Shell-gate job; see
`.claude/rules/ci-workflows.md` § "Skill-local harnesses are NOT auto-wired").
