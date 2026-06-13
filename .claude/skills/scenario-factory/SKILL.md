---
name: scenario-factory
description: Run one scenario-factory cycle — generate 3 fresh scenario YAMLs, execute each on pastura-harness with real local-LLM inference, judge the transcripts in-session, and append the committed digest. Use when the user asks to run the scenario factory, run a factory cycle, generate and field-test new scenarios, or dogfood scenarios overnight.
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
  the digest's promotion footer.
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
- Digest: `data/factory/digest.md` (committed — the cycle's only
  repo-visible artifact)
- Per-run timeout: `600` seconds (not the harness default 1800 — bounds a
  wedged run at 2 attempts × 600 s)
- Helper scripts: `.claude/skills/scenario-factory/scripts/`

## Step 0 — Preflight

1. `ls ~/Models/gemma-4-E2B-it-Q4_K_M.gguf` — abort with a clear message
   if the model is missing.
2. `command -v jq` — required by the run wrapper.
3. `swift build` once to warm the harness build (incremental afterwards).
   A build failure aborts the cycle — report it, do not generate.

## Step 1 — Read the digest (dedup)

Read `data/factory/digest.md`. Collect every past scenario **id, name,
theme, and comment** from the section tables. The new batch must not
repeat: same premise, same persona cast, or a theme judged ≤2 on humor
twice in a row. Low-scoring past entries are signals about what NOT to
generate again; high scorers indicate directions worth varying further.

## Step 2 — Generate 3 scenario YAMLs

Write 3 files to `data/factory/scenarios/<DATE>/<id>.yaml` with
`id: factory_<DATESTAMP>_<slug>` (snake_case slug, also the filename).

Theme: the **oogiri / comedy family** (current factory focus). Use the
bundled preset `Pastura/Pastura/Resources/Presets/bokete.yaml` as the
schema and tone reference, but vary the *format*, not just the topics —
e.g. constrained-form bokete (kigo / counting / forbidden-word rules),
role-mismatch interviews, deadpan product pitches, escalating excuse
battles. Each of the 3 scenarios should differ from the other 2 AND from
digest history in premise or mechanics, not merely in topic strings.

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
- Plain YAML only — no markdown fences in the file.

Inference budget — compute BEFORE writing each file:

```
per round: speak_all = agents | speak_each = agents × sub_rounds
           vote = agents     | choose = agents × 2 (round_robin) / agents
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

Failed runs get **no scores** — record the status and the wrapper's
`error` (skim the partial transcript only to classify the failure for
the comment). The judge is a quality filter, not a safety screen.

## Step 5 — Append the digest

1. Write the results JSON (schema documented in `append_digest.py`'s
   docstring: date / model / notes / per-scenario id, name, theme, yaml,
   run_log, status, attempts, duration_sec, scores, comment, error) to a
   temp file.
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
(`scenarios/<DATE>/`, `runs/<DATE>/`, digest diff). `data/factory/digest.md`
is left modified in the working tree — committing it (and any promotion
PR — bundled preset or shared-scenario gallery; see the digest's
promotion footer for the two channels) goes through the normal
`/orchestrate` flow; this skill does not commit or push.

## Scheduling (how the unattended nightly run works)

- **The skill never self-registers** (see Non-goals "No scheduled
  execution"). Scheduling is an operator action: a **Claude Desktop
  *local* Routine** invokes `/scenario-factory`. Cloud routines are
  unusable here — generation + judging burn the on-device llama.cpp +
  GGUF harness, which a cloud clone can't reach. (The prior 04:07
  CronCreate registration is abandoned: CronCreate's durable flag does
  not hold, so it expires within ~7 days.)
- **worktree toggle OFF — mandatory.** Unlike queue-consumer /
  consistency-audit (whose scheduled runs use a routine-provided
  worktree because they leave *nothing* in the working tree), the factory
  leaves `data/factory/digest.md` modified. Its `append_digest.py` takes
  a **required `--digest`** path and writes it verbatim — it does **not**
  resolve the main checkout via `git rev-parse --git-common-dir` the way
  queue-consumer's does. So under a worktree the append lands in the
  worktree copy and is **lost when the worktree is torn down**. Run OFF,
  in the main checkout. (This is the one bullet that *inverts* the
  consistency-audit § Scheduling shape — there worktree is ON, here it
  must be OFF, for that reason.)
- **Routine recipe** (Desktop → Routines → New routine):
  - **Type**: Local
  - **Name**: `scenario-factory-nightly`
  - **Working folder**: `/Users/tyabu12/Work/pastura`
  - **worktree toggle**: **OFF** (above)
  - **Schedule**: Daily, **4:07 AM** — clear of the queue-consumer 1:30
    window (factory's ~30 min run ends well before, and well after 1:30
    finishes). A shared checkout + local inference/sim contention means
    family routines must not overlap; future routines avoid this ±30 min
    window too.
  - **Permission mode**: set to **`acceptEdits`** (do not use
    `bypassPermissions`). `acceptEdits` auto-accepts the in-session file
    writes (generated YAMLs); least-privilege, matching the rest of the
    family.
  - **Instructions**: run the skill, then commit the digest **only when on
    `main`** (worktree-OFF means the run inherits whatever branch the main
    checkout sits on — without this guard a stray feature-branch checkout
    would receive the digest commit):

    ```bash
    /scenario-factory
    # then, the scheduling wrapper commits the cycle's only artifact.
    # No `set -e` on purpose: the `||` skip relies on continue-on-false,
    # and a detached HEAD makes symbolic-ref return "" (≠ main) so it
    # fails safe — leaving the digest uncommitted rather than mis-committing.
    [ "$(git symbolic-ref --quiet --short HEAD)" = "main" ] || {
      echo "not on main — leaving digest uncommitted"; exit 0; }
    git add data/factory/digest.md
    git commit -m "📝 chore: scenario-factory nightly digest"
    ```

    The commit lives in the **wrapper, not the skill body** — the skill's
    "does not commit or push" invariant stays intact, so a *manual*
    `/scenario-factory` still leaves the digest for a human to commit via
    `/orchestrate`. The scheduled run committing its own digest is the
    factory analogue of queue-consumer auto-creating its Draft PR (the
    digest is the cycle's only repo-visible artifact).
- **No settings.json change at schedule time.** `git add` / `git commit` /
  `swift build` are already allowlisted, and the factory helper scripts
  (`run_scenario.sh`, `append_digest.py`, `format_transcript.py`) are
  allowlisted too — so an unattended run needs no first-run "always
  allow" warming. Purely local: no `gh`, no network, no push.
- **Environment prerequisites**: AC power, the machine awake (non-sleep),
  and idle at fire time — the cycle burns local GGUF inference.
