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
"Scheduling" below); the digest always resolves to the main checkout.

This is the first generator of the "nightly brush-up automation" family. Its
**Output Contract** (below) is the reusable part — later generators (i18n
parity, code analysis, scenario fuzzing) inherit the same gating so they stay
safe to run unattended.

## Non-goals

- **The skill never self-registers a schedule.** Invocation is manual today;
  once an operator is confident, a *separate* `/schedule` routine invokes
  `/consistency-audit` (see "Scheduling" below). The unattended command set
  (`git switch -c audit/*`, the skill's `python3` scripts, `git push`,
  `gh pr create --draft`) is now allowlisted so a routine run does not block on
  those prompts. `git commit` is the exception — gated project-wide and
  deliberately not allowlisted, so a fully non-interactive run also relies on
  the eventual `/schedule` runner handling it. (`gh issue create` is likewise
  NOT allowlisted — Step 4 is unreachable while all needs_judgment detectors
  are deferred; a future detector author re-allowlists it deliberately.)
- **No merging, no issue closing.** The human reviews each Draft PR; merging
  closes nothing automatically here.
- **No parallelism — single writer.** One audit run at a time. Two overlapping
  runs could each observe zero open `audit/*` PRs and both open one (the Step 2
  dedup assumes a single writer; Step 3 adds a post-push race re-check as a
  second guard). Do not schedule overlapping audit runs, nor run a manual audit
  while a routine one may fire.

## Output Contract (reusable across the brush-up family)

1. **Mechanically-verifiable fix → docs-fix Draft PR.** A finding is
   auto-fixable only when the correct value is *uniquely determined by an
   authoritative source* (e.g. a dependency version from `Package.resolved`).
   Batch all such fixes from one run into a **single** `audit/<date>` Draft PR.
2. **Detected-but-judgment → issue only.** Anything where the fix needs a human
   decision (which target did a dead link mean?) is filed as an issue, never an
   auto-fix PR. The issue body MUST carry a **confidence score** and a
   **counter-evidence / "why this might be wrong"** section.
3. **The auto-fix path edits authoritative-source-computed values only — never
   free-form prose — and the edit is spliced at the detected token's exact
   offset, not by a free-text replace.** This is the bound that makes the
   omitted code-review (below) safe. Any future detector that wants to auto-fix
   something non-mechanical re-introduces a mandatory `code-reviewer` pass.
4. **Backpressure.** Generators must cap their own work-in-progress so the
   review queue never floods. For the auto-fix path that means **one open
   `audit/*` Draft PR at a time** — a run that finds one already open skips
   opening another (Step 2).
5. **Manual-first.** The detector is dry-run by default; only act after a human
   has eyeballed the dry-run output at least once for a given repo state.

### Why no `code-reviewer` pass here

queue-consumer makes code review mandatory because it writes arbitrary code.
This skill's auto-fix path writes *only* a version string computed from an
authoritative source, the PR is always **Draft**, and a human merges it — so
the human merge IS the review gate, and there is nothing for a reviewer to
assess on a one-token version swap. The safety rests on the Draft + human-merge
invariant and Contract rule 3, NOT on the diff being small. If rule 3 is ever
relaxed, restore the `code-reviewer` pass.

## Constants

- Detector: `.claude/skills/consistency-audit/scripts/audit_docs.py`
- Digest helper: `.claude/skills/consistency-audit/scripts/append_digest.py`
- Auto-fix PR branch: `audit/docs-<YYYYMMDD>` (collision fallback `-2`, `-3`, …)
- Auto-fix dedup: **at most one open `audit/*` Draft PR at a time.** A run that
  finds one open skips the auto-fix PR step and reports it pending — all fixes
  batch into one PR, so a second would duplicate the first.
- Label: `documentation` (for both PRs and issues)

## Hard rules (non-negotiable)

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
5. Working tree clean **except the digest** —
   `git status --porcelain -- . ':(exclude)data/audit/digest.md'` must be empty.
   A prior run leaves `data/audit/digest.md` modified by design (committed later
   via `/orchestrate`), so excluding it lets two consecutive unattended runs
   proceed without an intervening commit; any *other* dirty path means a prior
   run died mid-way — abort and report rather than mixing changes.

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
blocking PR's url in the report and digest ("auto-fix paused until #N is merged
or closed"). A stale unmerged audit PR therefore pauses *all* auto-fixes until a
human acts on it — intentional backpressure, made observable via the digest so
it does not silently disable the skill. Step 4 (issues) still runs.

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

For each `needs_judgment` finding (already deduped by target):

1. **Dedup across runs:** search open issues for the target; skip if one
   exists. `gh issue list --state open --search "<target> in:title"`.
2. File an issue (`--label documentation`) whose body has:
   - **Locations**: every `file:line` the target is referenced from.
   - **Confidence**: how sure the detector is this is a real problem.
   - **Counter-evidence / why this might be wrong**: e.g. the target may be an
     intentionally-absent path, a generated artifact, or a moved file whose
     correct new location only a human knows.
   - **Suggested action**, explicitly left for a human to decide.

Never auto-fix these — the whole point is the fix needs judgment.

## Step 5 — Report + digest

Summarize to the user / transcript: auto-fix PR url (or "skipped — open audit
PR #N pending" / "none"), issues filed (or skipped-as-duplicate), and the
dry-run counts. Point at `/tmp/audit.json` for the raw findings.

Then append one section to the run digest so scheduled runs leave a trail.
Compose a results file and run the helper:

```bash
cat > /tmp/audit_results.json <<JSON
{ "run_id": "<YYYY-MM-DD HH:MM>",
  "auto_fixable": <n>, "needs_judgment": <m>,
  "auto_fix_status": "opened|skipped-open-audit-pr|none",
  "auto_fix_pr": "<new-or-blocking PR url, or null>",
  "issues": [<filed issue urls>], "notes": "<optional>" }
JSON
python3 .claude/skills/consistency-audit/scripts/append_digest.py --results /tmp/audit_results.json
```

The helper resolves `data/audit/digest.md` in the **main checkout** (so a
worktree-based scheduled run still persists the record) and leaves it modified
there; committing it goes through the normal `/orchestrate` flow (mirrors
`data/queue/digest.md`).

## Scheduling (how unattended runs work)

- **Manual run** executes from the main checkout; a **scheduled run** executes
  inside a routine-provided worktree (the queue-consumer model) — fresh off
  `origin/main` each fire, so the clean-tree preflight passes and no branch or
  digest state accumulates in the run's checkout. The digest is written to the
  main checkout either way (`append_digest.py` resolves it via
  `--git-common-dir`).
- **Do not overlap the queue-consumer window.** Both skills require a
  (near-)clean tree and both leave a digest modified in the main checkout;
  whatever commits one digest must run before the other skill's preflight.
  Schedule the audit run in a separate window.
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
- **ADR-missing reference checks** — reserved/not-yet-written ADRs (ADR-006)
  are referenced from ~20 lines that lack the marker. Needs a canonical
  reserved-ADR set parsed from the ADR index, not a per-line marker.
- **broken-anchor / `§"..."` cross-refs** — GitHub-slug anchor matching is
  fragile on emoji headings and duplicate-heading suffixes; bare `§"..."` prose
  refs have no unambiguous target. Needs a verified slug normalizer + a target
  resolution rule.
