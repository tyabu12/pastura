---
name: consistency-audit
description: Detect mechanically-verifiable documentation/ADR drift and act on it — open a docs-fix Draft PR for fixes whose value is uniquely determined by an authoritative source, or file an issue (with confidence + counter-evidence) for drift that needs human judgment. Use when the user asks to run the consistency audit, audit the docs, check for doc/ADR drift, or run the nightly brush-up consistency pass.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# /consistency-audit

One consistency pass: **detect → triage → act**. The detector
(`scripts/audit_docs.py`) is read-only and prints JSON; this skill consumes
that JSON and decides what to do with each finding class. Run from the
repository root of the current checkout — a **manual** run from the main
checkout, or a **scheduled** run from a routine-provided worktree (see
"Scheduling" below).

This is the first generator of the "nightly brush-up automation" family. The
gating that keeps every generator safe to run unattended is the shared
**Output Contract**, canonical in `.claude/rules/automation-output-contract.md`
— **read it in full before Step 0.** It is path-scoped to `.claude/skills/**`,
which fires when a skill file is *read*, not when this one *runs* — a run drives
its scripts through Bash and never reads this file, so it executes without the
contract in context.

## Non-goals

- **The skill never self-registers a schedule.** Invocation is manual today;
  once an operator is confident, a *separate* `/schedule` routine invokes
  `/consistency-audit` (see "Scheduling" below). The unattended command set
  (`git switch -c audit/*`, the skill's `python3` scripts, `git push`,
  `gh pr create --draft`, `gh issue create`) is allowlisted so a routine run
  does not block on those prompts. `git commit` is allowlisted too — since #411
  the commit-time gate moved to the git pre-commit hook (`swiftlint --strict` +
  build), so there is no per-commit prompt. (`gh issue create` was allowlisted
  with the dangling-ADR detector (#876); every needs_judgment detector can
  file Step 4 issues. It is exercised only when one actually fires; on a clean
  `main` all of them are designed to report zero, so Step 4 stays quiet by
  construction, not because it is unreachable.)
- **No merging, no issue closing.** The human reviews each Draft PR; merging
  closes nothing automatically here.
- **No parallelism — single writer.** One audit run at a time. Two overlapping
  runs could each observe zero open `audit/*` PRs and both open one (the Step 2
  dedup assumes a single writer; Step 3 adds a post-push race re-check as a
  second guard). Do not schedule overlapping audit runs, nor run a manual audit
  while a routine one may fire.

## Output Contract

**Canonical text: `.claude/rules/automation-output-contract.md` — read it in
full before Step 0.** It is path-scoped to `.claude/skills/**`, which fires when a
skill file is *read*, not on this skill's *execution* — a run drives its scripts
through Bash without reading a skill file, so nothing auto-loads it during a
run.

How this skill binds itself to each rule:

- **Rule 1** (mechanical fix → one batched Draft PR) — the authoritative source
  is typically a dependency version from `Package.resolved`; all such fixes from
  one run batch into a single `audit/<date>` Draft PR.
- **Rule 2** (judgment → issue with confidence + counter-evidence) — "which
  target did this dead link mean?" is the canonical judgment case here.
- **Rule 3** (authoritative values only, spliced at the exact offset) — the
  bound that makes the omitted code-review below safe.
- **Rule 4** (backpressure) — this skill's own cap is **one open `audit/*` Draft
  PR at a time**; a run that finds one already open skips opening another
  (Step 2). The family-wide ceiling is Step 0.5.
- **Rule 5** (manual-first) — the detector is dry-run by default; only act after
  a human has eyeballed the dry-run output at least once for a given repo state.
- **Rules 0 and 6** — restated operationally as Hard rules below, where an
  unattended run finds them without following a pointer.

### Why no `code-reviewer` pass here

queue-consumer makes code review mandatory because it writes arbitrary code.
This skill's auto-fix path writes *only* a version string computed from an
authoritative source, the PR is always **Draft**, and a human merges it — so
the human merge IS the review gate, and there is nothing for a reviewer to
assess on a one-token version swap. The safety rests on the Draft + human-merge
invariant and Contract rule 3 — authoritative values only, spliced at the exact offset — NOT on the diff being small. If rule 3 is ever
relaxed, restore the `code-reviewer` pass.

## Constants

- Detector: `.claude/skills/consistency-audit/scripts/audit_docs.py`
- Auto-fix PR branch: `audit/docs-<YYYYMMDD>` (collision fallback `-2`, `-3`, …)
- Auto-fix dedup: **at most one open `audit/*` Draft PR at a time.** A run that
  finds one open skips the auto-fix PR step and reports it pending — all fixes
  batch into one PR, so a second would duplicate the first.
- Label: `documentation` (for both PRs and issues)

## Hard rules (non-negotiable)

Rules 1–3 restate Output Contract **rule 0** (never actuate) and rule 4 restates
**rule 6** (conservative detection), deliberately duplicated here as the
operational form: these are the hard-stop invariants an unattended run must not
have to follow a pointer to find.

Canonicality is a three-hop chain, and edits flow down it in order: claude-kit's
`docs/automation-output-contract.md` owns the generic core → this repo's
`.claude/rules/automation-output-contract.md` mirrors it one-way → this
restatement. So a change to the contract itself starts **upstream in the kit**,
never in the mirror (its reconcile header forbids becoming a source). Only a
Pastura-specific operational detail starts here.

1. **Never push to main. Never force push.** All pushes are
   `git push -u origin audit/...`. A PreToolUse guard hook also blocks
   `--force` shapes and `gh pr ready`.
2. **PRs are always Draft.** `--draft` is the first flag of `gh pr create`.
   Never run `gh pr ready`.
3. **Never close an issue.** Closing happens through the human's merge.
4. **Conservative detection wins.** Prefer a miss over a wrong flag — a wrong
   auto-fix PR or a false issue is worse than a missed inconsistency.

## Step 0 — Preflight (abort on any failure)

1. `gh auth status` succeeds.
2. `python3` and `jq` are available.
3. Label exists: `gh label list` contains `documentation`.
4. `git fetch origin main` (any auto-fix branch is cut from `origin/main`).
5. Working tree clean (`git status --porcelain` empty) — the skill leaves
   nothing in the working tree (its auto-fix commits land on a separate
   `audit/*` branch), so any dirty path means a prior run died mid-way;
   abort and report rather than mixing changes. (Sibling generators no
   longer dirty the tree — the nightly digests are gitignored local logs.)
6. **Read `.claude/rules/automation-output-contract.md` in full.** Abort if
   missing. It does not auto-load during a run (its `paths:` glob fires on a read the run
   never performs), so this is the only step that puts the contract in context.

## Step 0.5 — WIP backpressure (skip when the review queue is saturated)

The family's aggregate ceiling, on top of this skill's own cap-1 dedup
(Step 2): cap-1 bounds *this* skill's lane, the ceiling bounds the *sum* of
unreviewed Drafts across all generators.

```bash
# canonical: triage-guardian/SKILL.md § Backpressure — keep predicate + ceiling in sync
WIP=$(gh pr list --state open --draft --json headRefName \
  --jq '[.[] | select(.headRefName | test("^(audit|agent)/"))] | length')
```

If `WIP >= 5` (`AUTOMATION_WIP_CEILING`), **skip this run** — report
`throttled by WIP backpressure: <WIP>/5` and stop before Step 1. **Inert
today**: the aggregate max is 1 (audit) + 2 (agent) = 3 < 5, so this never fires
under the current roster; it is wired now so the next generator inherits
backpressure for free (same move as the Output Contract). **Advisory**: the
per-generator hard caps are the real guard, so the preflight-count race is
benign. The constant + predicate are defined canonically in
`.claude/skills/triage-guardian/SKILL.md` § Backpressure — change all three
referencing files together.

## Step 1 — Detect (dry-run)

```bash
python3 .claude/skills/consistency-audit/scripts/audit_docs.py --repo-root . > /tmp/audit.json
```

Read `/tmp/audit.json`. It has `auto_fixable` and `needs_judgment` arrays.
**This is the manual precision-check point** — on the first run for a given
repo state, an operator should sanity-read the findings before acting. If both
arrays are empty, report "no drift" and stop.

## Step 2 — Auto-fix dedup (at most one open audit PR)

```bash
OPEN_AUDIT=$(gh pr list --state open --json number,url,isDraft,headRefName \
  --jq '[.[] | select(.isDraft and (.headRefName | startswith("audit/")))]')
```

If any open `audit/*` Draft PR exists, **skip Step 3** — all auto-fixes batch
into one PR, so opening another would duplicate the pending one. Record the
blocking PR's url in the report ("auto-fix paused until #N is merged or
closed"). A stale unmerged audit PR therefore pauses *all* auto-fixes until a
human acts on it — intentional backpressure, made observable in the run report
so it does not silently disable the skill. Step 4 (issues) still runs.

## Step 3 — Auto-fixable → one Draft PR

Only if `auto_fixable` is non-empty AND Step 2 found no open `audit/*` PR:

1. Branch from the fetched base:
   `git switch -c audit/docs-<YYYYMMDD> origin/main` (fallback `-2` on collision).
2. Apply exactly the mechanical edits:
   ```bash
   python3 .claude/skills/consistency-audit/scripts/audit_docs.py --repo-root . --fix > /tmp/audit_fixed.json
   ```
3. Verify the drift is gone: re-run the detector (no `--fix`) and confirm
   `auto_fixable` is now empty. If not, abort and report — do not open a PR.
4. Commit: `📝 docs: sync drifted references (consistency-audit)`.
5. Push, then **race re-check** before opening the PR (a concurrent run may have
   opened an `audit/*` PR since Step 2 — the single-writer assumption is not
   locked):
   ```bash
   git push -u origin audit/docs-<YYYYMMDD>
   SIBLING=$(gh pr list --state open --json isDraft,headRefName \
     --jq '[.[] | select(.isDraft and (.headRefName|startswith("audit/")) and .headRefName != "audit/docs-<YYYYMMDD>")] | length')
   ```
   If `SIBLING` is non-zero, **abort without opening a PR** — a sibling won the
   race; leave the pushed branch for a human to reconcile and report it.
   Otherwise:
   ```bash
   gh pr create --draft --base main --label documentation \
     --title "📝 docs: sync drifted version references" --body ...
   ```
   PR body: one row per fix — `file:line`, what changed (old → new), and the
   authoritative source — plus a line stating the diff is machine-generated,
   Draft, and awaits human merge (the review gate; see Output Contract).

## Step 4 — needs_judgment → issues

For each `needs_judgment` finding (already deduped by `target`):

1. **Dedup across runs:** search open issues for the target; skip if one
   exists. `gh issue list --state open --search "<target> in:title"`. Every
   finding carries a `target` for this — for `dead_link` it is the link path,
   for `dangling_adr` it is the ADR id (`ADR-099`), for `embedded_source_mirror`
   it is the `<docfile>::<sourcepath>` composite (so the same source mirrored in
   two docs files two distinct issues), for `unparsed_adr_reservation` it is
   `reservation:ADR-NNN` and for `adr_roster_drift` `roster:ADR-NNN` (or
   `roster:<file>` for a shape drift) — embed `target` in the issue title
   verbatim.

   **The namespacing on the last two is load-bearing.** This search matches a
   title substring and cannot tell finding types apart, so a bare `ADR-NNN`
   would be permanently suppressed by the open `dangling_adr` issue it exists
   to explain — most likely exactly when both fire.
2. File an issue (`--label documentation`) whose body has:
   - **Locations**: every `file:line` the target is referenced from.
   - **Confidence**: how sure the detector is this is a real problem.
   - **Counter-evidence / why this might be wrong**: e.g. the target may be an
     intentionally-absent path, a generated artifact, or a moved file whose
     correct new location only a human knows.
   - **Suggested action**, explicitly left for a human to decide.

   Most detectors pre-author these fields. `dangling_adr`,
   `embedded_source_mirror`, `unparsed_adr_reservation` and `adr_roster_drift`
   findings already carry `confidence`, `counter_evidence`, and
   `suggested_action` on the JSON — use them verbatim rather than re-deriving.
   Each also carries one field naming what it found: `source` (the real file a
   mirrored block drifted from), `shape` (which reservation shape was seen),
   and `problems` (the list of roster/INDEX/disk disagreements for one ADR).
   `dead_link` does not, so author its confidence / counter-evidence at filing
   time as before.

Never auto-fix these — the whole point is the fix needs judgment.

## Step 5 — Report

Summarize to the user / transcript: auto-fix PR url (or "skipped — open audit
PR #N pending" / "none"), issues filed (or skipped-as-duplicate), and the
dry-run counts. Point at `/tmp/audit.json` for the raw findings. That summary is
the whole record — for a scheduled run it is the run history entry, and any
actual change is durably captured by the Draft PR; the skill leaves nothing
behind in the working tree.

## Scheduling (how unattended runs work)

- **Manual run** executes from the main checkout; a **scheduled run** executes
  inside a routine-provided worktree (the queue-consumer model) — fresh off
  `origin/main` each fire, so the clean-tree preflight passes and no branch
  state accumulates in the run's checkout.
- **Sibling-generator overlap is no longer a clean-tree hazard.** The nightly
  digests (`data/queue/digest.md`, `data/factory/digest.md`) are gitignored
  local logs, so a concurrent queue-consumer / scenario-factory run does not
  dirty the main checkout. A manual-run abort now only signals a genuinely
  dirty tree (a prior run died mid-way), not a sibling's in-flight digest.
- The skill still never registers itself — scheduling is a `/schedule` action a
  human takes after this lands.

## Deferred detectors (NOT implemented in v1)

Documented so a later PR can design out the false-positive source before
enabling. Each floods the reference-dense repo today:

- **file:line citation checks** — docs cite source-root-relative paths
  (`LLM/Foo.swift` meaning `Pastura/Pastura/LLM/Foo.swift`), GitHub org/repo
  slugs (`mattt/llama.swift`), external paths (`src/llama-grammar.cpp`), and
  property accessors (`TurnOutput.primaryText`). A repo-root existence check
  misreads all of these. Needs source-root resolution + a non-file exclusion.
- **broken-anchor / `§"..."` cross-refs** — GitHub-slug anchor matching is
  fragile on emoji headings and duplicate-heading suffixes; bare `§"..."` prose
  refs have no unambiguous target. Needs a verified slug normalizer + a target
  resolution rule.
