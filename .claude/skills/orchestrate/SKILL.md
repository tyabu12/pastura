---
name: orchestrate
description: Orchestrate feature implementation from plan to PR — worktree isolation, TDD, review, and PR creation.
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, EnterWorktree, ExitWorktree
argument-hint: "[description | issue-number | phase N]"
---

<!-- generated-from: claude-kit skills/orchestrate-creator/orchestrate-template.md sha256:1fbc1aadc87e reconciled:2026-08-21 -->

# /orchestrate

Orchestrate the full development workflow for Pastura: plan → issue → worktree → TDD implementation
→ review → PR.

> **Project-owned file, hand-reconciled against the claude-kit template.** Edit it freely; kit updates
> never touch it. Before accepting a back-port from `/claude-kit:orchestrate-creator`, read
> [`docs/agent-tooling/orchestrate-kit-reconciliation.md`](../../../docs/agent-tooling/orchestrate-kit-reconciliation.md)
> — the divergences an upgrade would silently undo. The traps behind the shorter wording here live in
> [`docs/agent-tooling/orchestrate-traps.md`](../../../docs/agent-tooling/orchestrate-traps.md).

## Constants

- `PLAN_MARKER`: `<!-- pastura-plan -->` — machine-readable marker embedded in issue plan comments
  for resumption detection. Project-unique by construction; never change it to a generic name.
- `OWNER_REPO`: `gh repo view --json nameWithOwner -q '.nameWithOwner'`. Resolve in Step 0, after
  pre-flight check 1 (which decides whether `gh` is usable at all).

## Project parameters

| Parameter | Value |
|---|---|
| Test command | `scripts/xcodebuild.sh test [-only-testing PasturaTests/<Class>]` — bare and cwd-relative, never behind `cd … &&`, an env-var prefix, or an absolute path (`.claude/rules/xcodebuild-cli.md`) |
| Lint command | `swiftlint lint --quiet --strict` |
| Commit-time gate | pre-commit hook (`scripts/*-gate.sh`, SwiftLint, build when the changeset needs it) |
| TDD | required — Engine / LLM test-first; Data / UI implement-then-test (CLAUDE.md § Testing Strategy) |
| Plan-critique agent | `claude-kit:critic`, passed `model: opus` (it carries no pin) |
| Review agent | `code-reviewer` (`.claude/agents/code-reviewer.md`) |

**Commit-gate note:** the pre-commit hook enforces quality at commit time — after a subagent's
changes, a diff spot-check suffices before committing; the hook is the gate.

## Step 0: Input Detection & Pre-flight

Interpret `$ARGUMENTS`:
- **`#N`**: Fetch issue via `gh issue view N`, use title/body as task spec. Check for an existing
  plan (Resumption Detection below).
- **`phase N`**: Read ONLY that Phase section of `docs/ROADMAP.md`.
- **(empty)**: Ask what to implement.
- **Other text**: Use as inline task description.

Derive: `TASK_TYPE` (`feat`/`fix`, default `feat`); `SLUG` (kebab-case, `^[a-z0-9][a-z0-9-]{0,36}$`;
sanitize or ask if it doesn't match).

### Resumption Detection (`#N` only)

1. Fetch issue comments, find `PLAN_MARKER`:
   ```bash
   gh api "repos/${OWNER_REPO}/issues/N/comments" --jq '.[] | select(.body | contains("<!-- pastura-plan -->")) | {id, body}' | tail -1
   ```
   Use the **last** match.
2. If found: set `RESUMING=true`, `ISSUE_NUMBER=N`, capture `COMMENT_ID`. Parse checkboxes
   (`- [x]` done vs `- [ ]` remaining), identify `NEXT_ITEM`. Extract `TASK_TYPE`, branch,
   `REVIEWER_MODEL`, `SESSION_MODEL` from the `## Metadata` block (normalize to lowercase
   `opus`/`sonnet`; default `opus` if a field is absent). Derive `SLUG` from the branch.
   - **Coupling re-check:** if the resumed plan has any Opus-tier item (`🎭` or `🧠`) but
     `REVIEWER_MODEL=sonnet` or `SESSION_MODEL=sonnet`, warn and offer to upgrade to Opus before
     continuing. If it is all Sonnet-tier with `REVIEWER_MODEL=sonnet`, re-confirm each item is
     strictly within the 🎵 simple criteria — a `🎵 (tb)` item is not, and the label alone does not
     establish it (Step 1.3) — and offer the same upgrade.
   - If **all items checked**: do **not** silently proceed to review. A fully-checked *last* plan
     usually means its PR already merged — and on an **umbrella issue** that accumulates several
     historical plan comments, `tail -1` lands on that finished plan, so auto-proceeding re-reviews
     completed work instead of planning the new work the user actually wants. Ask: *"#N's last plan
     is complete (its PR likely merged) — resume-review it, or start a NEW plan for new work on
     #N?"* Only ensure you are on the branch/worktree and **skip to Step 4** on explicit
     "resume-review"; otherwise treat as a fresh task (fall through to Step 1).
   - Report "Found plan on #N. {DONE}/{TOTAL} complete. Resuming from item {NEXT_ITEM}." **Skip
     Steps 1 and 1b** → go to Step 2.
3. If no plan: proceed normally.

**Pre-flight** (in order):
1. `gh auth status` — if unauthenticated, run in **degraded mode**: no issue, no checkpoint sync,
   **no resumption** (say so explicitly). Skip all `gh` steps; the plan lives only in-session.
2. `git status` — warn on uncommitted changes.
3. Verify on default branch (skip if `RESUMING`): `DEFAULT_BRANCH=$(gh repo view --json
   defaultBranchRef -q '.defaultBranchRef.name')`. Degraded-mode fallback must yield a **bare branch
   name**: `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||'` (if `origin/HEAD`
   is unset, `git remote set-head origin -a` first). If not on it, offer `git switch`.
4. `git pull --ff-only origin "$DEFAULT_BRANCH"` — warn on failure, don't block. Skip if `RESUMING`.
5. If already in a worktree, suggest `ExitWorktree` first (unless resuming into the matching one).

## Step 1: Plan — Gate G1

1. Read `CLAUDE.md` and (if phase work) the relevant `docs/ROADMAP.md` section.
2. Format the plan as a numbered checkbox list, one item = one planned commit. Label each item with
   the outcome of two independent questions — **tier** (which model) and **locus** (main session or
   subagent):
   - **Q1 — tier, by the nature of the work.** A **🎭 criterion** — new design patterns, actor
     isolation / `Sendable` decisions, changes spanning layers, work near a dependency-rule boundary
     (Engine ↔ Data), anything needing non-obvious architectural judgment → Opus tier. A **🎵
     criterion** — existing-pattern reuse (a new Handler mirroring an existing one), test-only
     changes following an existing test pattern, type/error-case additions, doc comments, minor
     fixes → Sonnet tier. Neither → deferred. The 🎭 criteria name the *nature* of the work, so a
     matching item stays Opus-tier however settled its spec is — that decides the model, never the
     locus.
   - **Q2 — locus, by specifiability.** Not "too hard for Sonnet?": difficulty or size alone does
     not pull an item into the main session. A subagent inherits none of this conversation, so ask:
     can you fill the Step 3 prompt slots *now* without a new design decision — target file(s), plus
     an existing pattern to mirror or an acceptance condition? Yes, even if hard → subagent. No, or
     you can't tell → main session (that specific uncertainty — not general unease). Also route to
     the main session when delegation prompt + verify overhead exceeds the work itself (single-line
     edits, short doc tweaks).
   - **Q3 — resolve:**

     | Q1 tier | Q2 locus | Label |
     |---|---|---|
     | Opus | subagent | `🎭` |
     | Opus | main session | `🧠` |
     | Sonnet | subagent | `🎵` |
     | Sonnet | main session | `🎵 (main)` — keeps its Sonnet tier |
     | deferred | subagent | `🎵 (tb)` — specifiable but unclassified |
     | deferred | main session | `🧠` — unresolved and unverified by anyone else ⇒ Opus |

   ```
   - [ ] 1. 🎵 <description> (`<primary-file-path>`)
   - [ ] 2. 🧠 <description> (`<primary-file-path>`)
   ```
   Present to the user; store as `PLAN_BODY`.
3. **Assign a reviewer model** (single choice for the whole PR). Force **Opus** if any item touches
   the **sensitive base**: dependency-rule boundaries; actor isolation / `Sendable` design; public
   protocol signatures or access modifiers; `AppRouter` / `Route` / navigation; `App/` code touching
   BG execution or `SimulationViewModel`; ADRs and `docs/specs/**`; `.github/workflows/**`,
   `scripts/**`, `CLAUDE.md`, `.claude/**`; content safety (`ContentFilter`,
   `PrivacyInfo.xcprivacy`, `Info.plist`); `Data/DatabaseManager+Migrations.swift`; integrity /
   crypto (`App/ReplayHashing.swift`, the GGUF SHA-256 check in `App/ModelManager.swift`); LLM
   backend code or prompt templates; design-system foundations (`docs/design/design-system.md`,
   `DesignTokens*.swift`).
   Otherwise **Sonnet** is acceptable only if every item is strictly within the 🎵 simple criteria —
   new `@Test` cases in an existing suite, docs under `docs/**`, a single-file refactor inside one
   layer, applying an existing design token to an existing view, a fix whose cause is already
   localized. **Test that independently — a 🎵 label does not certify it**, and a `🎵 (tb)` item
   never passes it (keep `Session: Sonnet` there — the cost lever survives an Opus reviewer).
   **Coupling rule:** any Opus-tier item (`🎭` or `🧠`) ⇒ reviewer MUST be Opus. Record in
   `## Metadata` as `- **Reviewer**: Opus (reason: …)`; store the reason tail as `REVIEWER_RATIONALE`.
4. **Assign a session model** (label-driven only): any Opus-tier item → `Session: Opus` (the
   orchestrator spot-checks and commits every `🎭` diff, so key on tier, not locus); every item
   Sonnet-tier (`🎵`, `🎵 (tb)`, `🎵 (main)` in any mix) → `Session: Sonnet` (recommended — the cost
   lever; the reviewer is set by step 3's own test, not by this choice). Record as
   `- **Session**: Sonnet (reason: every item is Sonnet-tier)`; store `SESSION_RATIONALE`. A Sonnet
   override is rejected when any item is Opus-tier (warn, keep Opus). `effort` is not recorded —
   it stays at the session default.
5. **Ask: "Proceed with this plan, reviewer-model, session-model?"**
   For single-commit changes, combine G1 and G2, but still run Step 1b first.

## Step 1b: Plan Critique (REQUIRED unless `RESUMING`)

Launch `Agent(subagent_type: "claude-kit:critic", model: "opus", …)` to review the plan for blind
spots. If the agent type does not resolve (plugin not installed or trusted), stop and surface that
rather than skipping silently.

> **Prompt:** "Review this implementation plan for the Pastura project. Focus on: scope creep beyond
> the current phase, dependency-rule violations in the planned file locations, missing edge cases,
> integration risks with existing modules, and assumptions not validated against the codebase. If the
> plan declares a reviewer-model choice, add an axis evaluating whether it matches the sensitivity of
> the touched paths, and whether each item's label (tier and locus) matches the work it describes.
> Read the repo's `CLAUDE.md` and `docs/ROADMAP.md` for context.
> Task: {TASK_DESCRIPTION}
> Plan: {PLAN_BODY}
> Output your full two-stage evaluation (axes, evaluation, summary table, top actions)."

- **Any Critical verdict:** present the report, **ask "revise or proceed?"**. Revise → back to
  Step 1, regenerate, re-run 1b.
- **OK/Warning only:** present the summary as context, proceed to Step 2.

## Step 2: Issue + Worktree — Gate G2

### 2a: Issue & Plan Comment

- **`RESUMING`:** skip.
- **Degraded mode (unauthenticated):** skip; keep the plan in-session (no resumption).
- **From `#N`:** post the plan as a comment on `#N`:
  ```bash
  COMMENT_ID=$(gh api "repos/${OWNER_REPO}/issues/N/comments" \
    -f body="$(cat <<'PASTURA_PLAN'
  <!-- pastura-plan -->
  ## Implementation Plan

  {PLAN_BODY}

  ## Metadata
  - **Type**: {TASK_TYPE}
  - **Branch**: `{TASK_TYPE}/{SLUG}`
  - **Reviewer**: {REVIEWER_MODEL} (reason: {REVIEWER_RATIONALE})
  - **Session**: {SESSION_MODEL} (reason: {SESSION_RATIONALE})
  PASTURA_PLAN
  )" --jq '.id')
  ```
  Title-case model names in Metadata; Step 0 normalizes on read.
- **Otherwise (new task):** create an issue (`gh issue create --title "{EMOJI} {TASK_TYPE}: {TITLE}"
  --assignee "@me" [--label "$LABEL"] --body …`), extract `ISSUE_NUMBER`, then post the plan as the
  first comment (capture `COMMENT_ID`). **Label fallback:** if `--label` fails (label absent in the
  repo), retry without it (or offer to create the label) — never block on a missing label.

### 2b: Worktree Setup

- **`RESUMING`:** find existing worktree (`git worktree list | grep {SLUG}`) → `EnterWorktree`; else
  recreate from the remote branch; else fresh. If `SESSION_MODEL=sonnet`, prompt `/model sonnet`
  first, then **ask "Resume from item {NEXT_ITEM}/{TOTAL}?"**
- **Normal:**
  1. "Issue #{ISSUE_NUMBER} created. Branch: `{TASK_TYPE}/{SLUG}`" (or, degraded, just the branch).
  2. If `SESSION_MODEL=sonnet`, tell the user to run `/model sonnet` now (or keep Opus). Then **ask
     "Create worktree and start?"**
  3. `EnterWorktree` with `name: "{TASK_TYPE}/{SLUG}"` (on collision, check `git ls-remote --heads
     origin <branch>`, append `-2`).
  4. Rename to conventional format: `git branch -m "$(git branch --show-current)" "{TASK_TYPE}/{SLUG}"`.
  5. Verify: `git branch --show-current`.

**Worktree path hygiene** (holds for the rest of the session): the original checkout stays on another
branch, so a tool that resolves to it instead of this worktree acts on the wrong tree silently.
cwd inheritance for a non-isolation subagent is **not guaranteed** (it has resolved to the *original*
checkout in practice, yielding an empty phantom diff that reads as a false FAIL). So capture the root
once with `WORKTREE_ROOT=$(git rev-parse --show-toplevel)` and **embed `git -C {WORKTREE_ROOT}`** into
every subagent prompt that runs git — never a bare `git` the subagent resolves against its own cwd,
never a `$(…)` it re-runs, never a reused pre-worktree path. Same rule for absolute Edit/Write paths:
resolve them under `{WORKTREE_ROOT}`, and invalidate any carried over from a *pre-worktree* result.
`-C` is git-only: `scripts/xcodebuild.sh` stays bare (Project parameters), so have a delegated
implementer **report `pwd`** — the wrapper resolves its root from cwd, and a run that landed in the
main checkout returns a green for the wrong tree.

## Step 3: Implementation

Follow the plan. If `RESUMING`, start from `NEXT_ITEM`. Per item (`K` = plan item number), branch on
the label:

| Label | Branch |
|---|---|
| `🧠` | in-session — the orchestrator implements it |
| `🎭` | `Agent(subagent_type: "claude-kit:implementer", model: "opus")` |
| `🎵` / `🎵 (tb)` | `Agent(model: "sonnet")` |
| `🎵 (main)` | the in-session branch, at the session model |

### In-session — orchestrator implements directly

1. Write the test first — TDD is required in this project. Skip only for docs-only / test-only items.
2. Run `scripts/xcodebuild.sh test -only-testing PasturaTests/<Class>` — confirm red.
3. Write the implementation.
4. Run the same command — confirm green.
5. Commit (Conventional Commits + emoji per CLAUDE.md).
6. **Checkpoint sync** (skip in degraded mode) — check off item `K` in the plan comment:
   ```bash
   BODY=$(gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" --jq '.body')
   UPDATED=$(echo "$BODY" | sed "s/^- \[ \] ${K}\./- [x] ${K}./")
   gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" -X PATCH -f body="$UPDATED" --jq '.url'
   ```
   On `gh` failure, **warn and continue** — never block on a sync failure.

### Delegated — `🎭` Opus implementer or `🎵` Sonnet subagent

Launch **without `isolation`** (shares the worktree). Subagents run **sequentially**, never in
parallel. Give a `🎵` subagent `Read, Grep, Glob, Bash, Write, Edit` — NOT `EnterWorktree` /
`ExitWorktree`. `claude-kit:implementer` declares no `tools:` key and pins `effort: medium`, so the
`🎭` prompt adds the two lines marked below. If the agent type does not resolve, stop and surface
that — never quietly implement the item in-session instead. Bound the delegated scope so the item
stays reviewable in one pass (split budget: `.claude/agents/code-reviewer.md`).

> **Prompt template:** "You are implementing item {K} of a plan for the Pastura iOS project.
> Work inside `{WORKTREE_ROOT}` — treat every path below as rooted there and run git via
> `git -C {WORKTREE_ROOT}`; run `scripts/xcodebuild.sh` bare from that directory, never behind `cd`,
> an env-var prefix, or an absolute path; do not rely on inherited cwd. Run `pwd` first and confirm
> it is `{WORKTREE_ROOT}`.
> **Read the repo's `CLAUDE.md` first** — follow all its conventions.
> **Task:** {ITEM_DESCRIPTION}. **Target file(s):** {PRIMARY_FILE_PATH}.
> **Reference:** {existing similar file to mirror, if any}.
> Procedure: if implementation, write/adjust the test in `PasturaTests/`, run
> `scripts/xcodebuild.sh test -only-testing PasturaTests/{TestClass}`, confirm it fails, implement,
> run again, confirm it passes. If docs-only or test-only, make the change directly. **Do NOT
> commit** — leave changes unstaged; the orchestrator reviews and commits. If tests still fail after
> your best effort, return a summary of what you tried and the error output.
> *(🎭 only)* Do not call `EnterWorktree`, `ExitWorktree`, or `Agent`. End your report with one line:
> `OUTCOME: done | design-decision | scope-refusal | failed`, and state whether you left modified or
> new files in the worktree."

**After the subagent returns:**
1. `git status` — verify expected changes only.
2. Read `git diff` fully before writing the commit message. Where the item removes or changes a
   shape, grep the file for the OLD shape — the prompt bounded what was *asked*, not what the item
   *mandates*.
3. **Gate:** a convention spot-check suffices — the pre-commit hook enforces the rest.
4. Commit.
5. Checkpoint sync (same PATCH as above; skip in degraded mode).

**`🎭` outcomes other than `done`:** `design-decision` — settle it yourself and finish the item
in-session; keep the partial work (no stash). `scope-refusal` — no partial work exists; re-split the
item and dispatch the pieces. `failed` — the fallback below.

**Fallback (subagent could not make tests pass):** take over immediately — do not retry the same
tier. `git stash -u` to save partial work, then escalate **by session model**: `SESSION_MODEL=opus`
→ orchestrator finishes it in-session; `SESSION_MODEL=sonnet` → delegate to
`Agent(subagent_type: "claude-kit:implementer", model: "opus")` (no `isolation`) with the item spec +
the error output; on return, review the diff and commit. If Opus also fails, report and offer
`/model opus` + retry directly.

**After all items,** run full verification from the main session: `scripts/xcodebuild.sh test
--tail 80` (the wrapper's pipefail-safe cap — no external `| tail`), then `swiftlint lint --quiet
--strict`. On failure, fix, verify locally, commit with `🐛 fix:`, re-run. **Hard limit: 3
iterations** — if still failing, report and ask whether to proceed to Step 4.

> **Carve-out — build-irrelevant branches:** the skip predicate is mechanical:
> `git -C {WORKTREE_ROOT} diff --name-only {DEFAULT_BRANCH}...HEAD | scripts/precommit-gate-classify.sh`
> (expect one approval prompt). No `build` token ⇒ skip the suite; no `lint` token ⇒ skip SwiftLint.
> CI's PR path-gating reuses the same script, so it is not a backstop — state the skip in the PR body.

## Step 4: Review — Gate G3

**Before launching the reviewer,** `git fetch origin {DEFAULT_BRANCH}` and check `git rev-list --count
HEAD..origin/{DEFAULT_BRANCH}`. If non-zero, offer a rebase before review; treat it as **mandatory**
when the diff touches large generated / data files (`Localizable.xcstrings`, lockfiles), where a
rebase or non-conflicting auto-merge can drop upstream entries without surfacing a conflict.

Launch `Agent(subagent_type: "code-reviewer", model: "$REVIEWER_MODEL", …)` (lowercase
`opus`/`sonnet`, from Metadata; defaults Opus). The reviewer MUST emit a `**Verdict**: PASS | FAIL`
line — the gate below parses it. Its scope budget counts **added** lines; if it returns
`SCOPE_TOO_LARGE`, split by added lines (per area or per axis) — never downgrade `REVIEWER_MODEL`
to fit a diff.

> **Prompt:** "Review all changes on this feature branch. Run **`git -C {WORKTREE_ROOT} diff
> {DEFAULT_BRANCH}...HEAD`** for the full diff (all commits since branching) — use the `-C` path, do
> not rely on cwd; a bare `git` can resolve to the original checkout and show an empty phantom diff.
> Read every changed file in full. Evaluate against your complete checklist. Output your review in
> your standard format, including a `**Verdict**: PASS | FAIL` line."

**One round.** The review is input to the orchestrator's judgment, not a loop:
1. **PASS** → Step 5.
2. **FAIL** → triage every finding **in the main session** — no verification subagent. For each:
   *apply*, or *reject with a one-line reason* (false positive, out of scope, or a disagreement you
   will stand behind in the PR). Capture `FIX_BASE=$(git rev-parse HEAD)`, apply the accepted
   findings, commit `🐛 fix:`.
3. **Re-review at most once, and only the fix diff** (`git -C {WORKTREE_ROOT} diff
   {FIX_BASE}...HEAD` plus the prior findings) — and only when a fix introduced new logic rather
   than applying the reviewer's own suggestion. Findings from that pass are triaged the same way;
   there is no third round.
4. Every rejected or unfixed finding goes into the PR body's `## Review` section (Step 5). A
   residual Critical the user should weigh is stated there, not silently dropped.

## Step 5: PR Creation

Degraded mode: skip — report the branch is ready to push/PR manually, stop.

Base branch: `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`. Label from the
dominant commit prefix (`feat→enhancement`, `fix→bug`, `docs→documentation`, `refactor→refactor`,
`test→testing`, `chore→chore`, `ci→ci`, `perf→performance`); add `security` if security-related.
**If the label doesn't exist in the repo, drop it** (same fallback as Step 2a).

Present the PR draft (informational; created automatically, no gate):
- Title: emoji prefix + Conventional format, < 70 chars.
- Body: `## Summary`, `## Test plan` (name any skipped suite and why), `## Review` (reviewer model;
  findings applied / rejected with reasons), `## Device QA`, and the issue link (omit in degraded
  mode). Use `Closes #N` **only when this PR completes the issue**; for a non-final PR of a
  multi-PR / umbrella issue, use `Part of #N`.
- `## Device QA` — on-device steps are required when the diff touches a surface the simulator cannot
  exercise: `#if !targetEnvironment(simulator)` blocks (enumerate with `git grep`), Metal / llama.cpp
  inference paths (`LlamaCppService`, GGUF load), or a Pattern-6 executor freeze
  (`.claude/rules/swift-isolation.md`). List the concrete steps; otherwise a single `実機QA不要` line
  with the one-line reason.

Compose the body in a file and pass `--body-file` (an inline heredoc trips the push-protection hook's
body scan). **Push and create as two separate Bash calls** — never combine with `&&` (a leading
`git push` breaks the `gh pr create --base`-anchored PR hooks):
```bash
git push -u origin <branch>
```
```bash
gh pr create --base "$BASE_BRANCH" --assignee "@me" [--label "$LABEL"] --title "..." --body-file <path>
```
After creation: print the PR URL; "wait for required checks, then merge manually."

## Step 6: Cleanup

**After merge** (guidance only — do NOT auto-execute): `ExitWorktree` action `"remove"`;
`git switch <default-branch> && git pull`.

> **Post-merge `remove` may refuse:** Pastura squash-merges, so the merged commit has a **new SHA** and
> the worktree's local commits read as unmerged by ancestry — `ExitWorktree(action: "remove")`
> refuses, as it also can *before* the post-merge `pull`. Once the user confirms the merge landed,
> re-invoke with `discard_changes: true`.
