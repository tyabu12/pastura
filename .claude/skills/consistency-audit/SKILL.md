---
name: consistency-audit
description: Detect mechanically-verifiable documentation/ADR drift and act on it — open a docs-fix Draft PR for fixes whose value is uniquely determined by an authoritative source, or file an issue (with confidence + counter-evidence) for drift that needs human judgment. Use when the user asks to run the consistency audit, audit the docs, check for doc/ADR drift, or run the nightly brush-up consistency pass.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# /consistency-audit

One consistency pass: **detect → triage → act**. The detector
(`scripts/audit_docs.py`) is read-only and prints JSON; this skill consumes
that JSON and decides what to do with each finding class. Run from the
repository root of the current checkout.

This is the first generator of the "nightly brush-up automation" family. Its
**Output Contract** (below) is the reusable part — later generators (i18n
parity, code analysis, scenario fuzzing) inherit the same gating so they stay
safe to run unattended.

## Non-goals

- **No scheduled execution.** Invocation is manual. The skill never registers
  itself. Scheduling lands in a later PR, *after* the operator has validated
  precision by hand. Until then, the skill's `git push` / `gh pr create` /
  `gh issue create` calls are NOT on the permission allowlist and will prompt
  — that human gate is intentional during manual rollout.
- **No merging, no issue closing.** The human reviews each Draft PR; merging
  closes nothing automatically here.
- **No digest yet.** Run history (a `data/audit/digest.md`) is deferred to the
  scheduling PR, where unattended runs actually need a trail.

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
   free-form prose.** This is the bound that makes the omitted code-review
   (below) safe. Any future detector that wants to auto-fix something
   non-mechanical re-introduces a mandatory `code-reviewer` pass.
4. **Backpressure.** Generators must cap their own work-in-progress so the
   review queue never floods (see WIP cap below).
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
- Auto-fix PR branch: `audit/docs-<YYYYMMDD>` (collision fallback `-2`, `-3`, …)
- WIP cap: **5** open `audit/*` Draft PRs. At or above the cap, skip the
  auto-fix PR step entirely (still report). Tune by editing this number.
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
5. Working tree clean (`git status --porcelain` empty) — a dirty tree means a
   prior run died mid-way; abort and report rather than mixing changes.

## Step 1 — Detect (dry-run)

```bash
python3 .claude/skills/consistency-audit/scripts/audit_docs.py --repo-root . > /tmp/audit.json
```

Read `/tmp/audit.json`. It has `auto_fixable` and `needs_judgment` arrays.
**This is the manual precision-check point** — on the first run for a given
repo state, an operator should sanity-read the findings before acting. If both
arrays are empty, report "no drift" and stop.

## Step 2 — WIP cap

```bash
OPEN_AUDIT=$(gh pr list --state open --json isDraft,headRefName \
  --jq '[.[] | select(.isDraft and (.headRefName | startswith("audit/")))] | length')
```

If `OPEN_AUDIT >= 5`, **skip Step 3** (do not open another auto-fix PR) and say
so in the report — the queue is full; merge or close existing `audit/*` PRs
first. Step 4 (issues) still runs.

## Step 3 — Auto-fixable → one Draft PR

Only if `auto_fixable` is non-empty AND under the WIP cap:

1. Branch from the fetched base:
   `git switch -c audit/docs-<YYYYMMDD> origin/main` (fallback `-2` on collision).
2. Apply exactly the mechanical edits:
   ```bash
   python3 .claude/skills/consistency-audit/scripts/audit_docs.py --repo-root . --fix > /tmp/audit_fixed.json
   ```
3. Verify the drift is gone: re-run the detector (no `--fix`) and confirm
   `auto_fixable` is now empty. If not, abort and report — do not open a PR.
4. Commit: `📝 docs: sync drifted references (consistency-audit)`.
5. Push and open a Draft PR:
   ```bash
   git push -u origin audit/docs-<YYYYMMDD>
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

## Step 5 — Report

Summarize to the user / transcript: auto-fix PR URL (or "skipped: WIP cap" /
"none"), issues filed (or skipped-as-duplicate), and the dry-run counts. Point
at `/tmp/audit.json` for the raw findings.

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
