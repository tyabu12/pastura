---
name: orchestrate
description: Orchestrate feature implementation from plan to PR — worktree isolation, TDD, review, and PR creation.
model: opus
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, EnterWorktree, ExitWorktree
argument-hint: "[description | issue-number | phase N]"
---

# /orchestrate

Orchestrate the full development workflow: plan → issue → worktree → TDD implementation → review → PR.

## Constants

- `PLAN_MARKER`: `<!-- pastura-plan -->` — machine-readable marker embedded in Issue plan comments for detection during resumption.
- `OWNER_REPO`: derived at runtime via `gh repo view --json nameWithOwner -q '.nameWithOwner'`. Resolve early in Step 0 (before any `gh api` calls).

## Step 0: Input Detection & Pre-flight

Interpret `$ARGUMENTS`:
- **`#N`** (digits after `#`): Fetch issue via `gh issue view N`, use title/body as task spec. Then check for an existing plan (see **Resumption Detection** below).
- **`phase N`** (e.g., `phase 1`, `phase 2`): Read ONLY that Phase section from `docs/ROADMAP.md`.
- **(empty)**: Ask user what to implement.
- **Other text**: Use as inline task description.

Derive from the task spec:
- `TASK_TYPE`: `feat` or `fix` (infer from content, default `feat`)
- `SLUG`: kebab-case, **must match `^[a-z0-9][a-z0-9-]{0,36}$`**. If not, sanitize or ask user.

### Resumption Detection (for `#N` input only)

After fetching the issue, check for an existing plan comment:
1. Fetch issue comments and search for `PLAN_MARKER`:
   ```bash
   gh api "repos/${OWNER_REPO}/issues/N/comments" --jq '.[] | select(.body | contains("<!-- pastura-plan -->")) | {id, body}' | tail -1
   ```
   Use the **last** matching comment (handles multiple plan comments from retries).
2. If a plan comment is found:
   - Set `RESUMING=true`, `ISSUE_NUMBER=N`, and capture `COMMENT_ID`.
   - Parse checkboxes: count `- [x]` (done) vs `- [ ]` (remaining). Identify `NEXT_ITEM` (first unchecked item number).
   - Extract `TASK_TYPE`, branch name, and `REVIEWER_MODEL` from the `## Metadata` section in the comment. **Normalize `REVIEWER_MODEL` to lowercase** (`opus` / `sonnet`) when binding — Metadata records it title-case (`Opus` / `Sonnet`) for readability, but downstream Agent calls use lowercase. If `Reviewer` is absent from Metadata (e.g., older plan comment pre-dating this field), default `REVIEWER_MODEL=opus`.
   - Derive `SLUG` from the branch name.
   - **Coupling re-check**: if the resumed plan contains any `🔴` item but `REVIEWER_MODEL=sonnet` (e.g., from a post-plan Metadata edit that bypassed the Step 1 coupling rule), warn the user and offer to upgrade to Opus before continuing — that is, before proceeding to Step 2 in the normal flow, or before the Step 4 review when all items are already complete. Reason: Opus-implemented items should never be Sonnet-reviewed.
   - If **all items are already checked**: ensure you are on the feature branch or in the correct worktree, then report "All {TOTAL} items already complete. Proceeding to review." and **skip to Step 4** directly.
   - Report to user: "Found existing plan on issue #N. {DONE}/{TOTAL} items complete. Resuming from item {NEXT_ITEM}."
   - **Skip Step 1 and Step 1b entirely** → proceed to Step 2.
3. If no plan comment found: proceed normally (Step 1 creates the plan, Step 2 attaches it).

**Pre-flight checks** (run in order):
1. `gh auth status` — warn and skip GitHub steps if unauthenticated.
2. `git status` — warn if uncommitted changes exist.
3. Verify on default branch (skip if `RESUMING=true`):
   - `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')`
   - If current branch != `DEFAULT_BRANCH`, warn and offer `git checkout "$DEFAULT_BRANCH"`.
4. `git pull --ff-only origin "$DEFAULT_BRANCH"` — warn on failure, don't block. Skip if `RESUMING=true`.
5. If already in a worktree, warn and suggest `ExitWorktree` first (unless `RESUMING=true` and the worktree matches the expected branch).

## Step 1: Plan — Gate G1

1. Read `CLAUDE.md` for current phase and conventions.
2. If phase-related, read ONLY the relevant Phase section from `docs/ROADMAP.md`.
3. Format the plan as a numbered checkbox list (each item = one planned commit).
   Assign a **complexity label** to each item:
   - 🟢 **simple** — Delegated to a Sonnet subagent. Criteria: existing pattern reuse (e.g., new Handler mirroring an existing one), test-only changes following an existing test pattern, type/error case additions, doc comments, minor fixes.
   - 🔴 **complex** — Implemented by the orchestrator (Opus) directly. Criteria: new design patterns, actor isolation / Sendable design decisions, changes spanning multiple layers, work near dependency rule boundaries (Engine ↔ Data), or any item requiring non-obvious architectural judgment.
   - **When in doubt, classify as 🔴.** Misclassifying a complex item as simple wastes a Sonnet attempt + Opus fallback; the reverse just costs extra Opus tokens.
   - **Skip delegation when overhead exceeds the work.** Promote a 🟢 item to 🔴 when subagent prompt + verify overhead likely exceeds the implementation itself — e.g. single-line edits, short doc tweaks. This forces Opus reviewer via the Coupling Rule below — intended, since the orchestrator is implementing the item directly.

   ```
   - [ ] 1. 🟢 <description> (`<primary-file-path>`)
   - [ ] 2. 🔴 <description> (`<primary-file-path>`)
   ...
   ```
   Present this plan to the user. Store internally as `PLAN_BODY` for Issue attachment in Step 2.
4. **Assign a reviewer model** for the PR as a whole (single choice, not per-item). This determines which model runs the `code-reviewer` subagent at Step 4. Criteria:

   **Opus required if any plan item touches:**
   - Dependency rule boundaries (Engine ↔ LLM ↔ Data ↔ Models interrelations)
   - Actor isolation / `Sendable` / `@MainActor` / `nonisolated` design
   - Public protocol signatures or access modifier changes
   - AppRouter / navigation routing (`Route` enum, `router.push` callsites)
   - `App/` layer changes touching BG execution, `SimulationViewModel`, or `AppRouter`
   - Decision records (`docs/decisions/ADR-*.md`) or architectural specs (`docs/specs/**`)
   - CI / build infrastructure (`.github/workflows/**`, `scripts/**`)
   - Project tooling (`CLAUDE.md`, `.claude/{skills,agents,rules}/**`)
   - Content safety surface (ADR-005 related: `ContentFilter`, `PrivacyInfo.xcprivacy`, `Info.plist`)
   - LLM backend code or prompt templates
   - Design system foundations (`docs/design/design-system.md`, `DesignTokens*.swift`)

   **Sonnet reviewer acceptable** — the change must be strictly a subset of the 🟢 simple-item criteria above (existing pattern reuse, test-only changes following an existing pattern, type/error case additions, doc comments, minor fixes), AND none of the items match the Opus-required list. Concretely, the most common Sonnet-acceptable shapes are:
   - New `@Test` cases in an **existing** suite following the file's existing pattern (not new suites, new helpers, or trait changes like `.timeLimit` / `.serialized`)
   - Documentation updates (`docs/ROADMAP.md`, `docs/examples/**`, `docs/gallery/**`, `docs/prototype/**`, doc comments)
   - Simple refactor within a single file without crossing layer boundaries
   - Design token **application** (existing token to existing View only — new token additions are Opus-required)
   - Fix-only PRs where the cause is already diagnosed and localized

   **Coupling rule:** If **any** plan item is labeled 🔴, the reviewer MUST be Opus — even if the target paths look Sonnet-eligible. This prevents the "all-🟢-plus-Sonnet-reviewer" configuration from putting Opus-implemented work through a Sonnet review.

   **When in doubt, pick Opus.** Subtle convention violations (ShapeStyle+Color token trap, `nonisolated` gaps, i18n `String(localized:)` omissions, missing `@Suite(.timeLimit(.minutes(1)))` on new test suites) cost more than an over-zealous Opus review.

   Record the decision in the `## Metadata` block of the plan comment (see Step 2a) as:
   ```
   - **Reviewer**: Opus (reason: touches Engine/ dependency boundary)
   ```
   Store the rationale string as `REVIEWER_RATIONALE` (the `(reason: ...)` tail) for use in the Step 2a template. The user may override at G1. Resumed sessions recover the decision from `## Metadata` (see Step 0).
5. **Ask: "Proceed with this plan and reviewer-model choice?"** — present both the plan checkboxes and the proposed `Reviewer:` decision so the user can override the reviewer at G1. For single-commit fixes, combine G1 and G2 into one confirmation, but still run Step 1b (critic review) before creating the worktree.

After user approval, proceed to Step 1b (mandatory critic review).

## Step 1b: Plan Critique (REQUIRED)

**⚠️ MANDATORY (unless `RESUMING=true`): You MUST complete this step before proceeding to Step 2.**

After the user approves the plan (G1), launch a `critic` subagent via the Agent tool to review the plan for blind spots.

> **Agent prompt:** "Review the following implementation plan for the Pastura project. Focus on: scope creep beyond current phase, dependency rule violations in the planned file locations, missing edge cases, integration risks with existing modules, and assumptions not validated against the codebase. If the plan declares a reviewer-model choice, include an axis evaluating whether that choice matches the actual sensitivity of the touched paths.
>
> Task: {TASK_DESCRIPTION}
>
> Plan:
> {PLAN_BODY}
>
> Read `CLAUDE.md` and `docs/ROADMAP.md` for project context. Output your full two-stage evaluation (Stage 1 axes, Stage 2 evaluation, Summary Table, Top Actions)."

Handle the critic's output:
- **Any Critical verdict**: Present the full critic report. **Ask: "Critic found critical issues — revise the plan, or proceed anyway?"** If revise → return to Step 1, regenerate plan, then re-run Step 1b. If proceed → continue to Step 2.
- **Only OK / Warning verdicts**: Present the summary table as informational context, then proceed to Step 2 without an additional gate.

*Skipped when `RESUMING=true`* (plan was already approved and critiqued in a prior session).

## Step 2: Issue + Worktree — Gate G2

**Precondition:** Step 1b critic review completed (or `RESUMING=true`).

### 2a: Issue & Plan Comment

**If `RESUMING=true`** (plan already exists on issue `#N`):
- Skip issue creation and plan attachment entirely.

**If from `#N`** (existing issue, no plan yet):
- Post the plan as a comment on issue `#N`:
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
  PASTURA_PLAN
  )" --jq '.id')
  ```
  Set `ISSUE_NUMBER=N`. When emitting `{REVIEWER_MODEL}` into Metadata, title-case the value (`Opus` / `Sonnet`) for readability — Step 0's parser normalizes back to lowercase on read.

**Otherwise** (new task — always create issue, because checkpoint sync and resumption require a `COMMENT_ID` on a real Issue):
- Determine `LABEL` from `TASK_TYPE` using the label mapping table in Step 5.
- Create a new issue:
  ```bash
  ISSUE_URL=$(gh issue create \
    --title "{EMOJI} {TASK_TYPE}: {TITLE}" \
    --assignee "@me" \
    --label "$LABEL" \
    --body "$(cat <<'PASTURA_ISSUE'
  ## Summary
  {1-3 sentence summary from plan}

  **Branch**: \`{TASK_TYPE}/{SLUG}\`

  See first comment for implementation checklist.
  PASTURA_ISSUE
  )")
  ```
  Extract `ISSUE_NUMBER` from the URL.
- Post the plan as the first comment (same format as the `#N` case above). **Capture `COMMENT_ID` from the response** (`--jq '.id'`) — it is required for checkpoint sync in Step 3.

### 2b: Worktree Setup

**If `RESUMING=true`**:
1. Check for existing worktree: `git worktree list | grep {SLUG}`.
2. If found → `EnterWorktree` with the existing worktree name.
3. If not found but branch exists remotely → fetch the branch and create a new worktree from it.
4. If nothing exists → create a new worktree (normal flow).
5. **Ask: "Resume from item {NEXT_ITEM}/{TOTAL}?"**

**Otherwise** (normal flow):
1. Display: "Issue #{ISSUE_NUMBER} created. Branch: `{TASK_TYPE}/{SLUG}`"
2. **Ask: "Create worktree and start?"**
3. Call `EnterWorktree` with `name: "{TASK_TYPE}/{SLUG}"`.
   - On failure: suggest alternative name or cleanup. Check `git ls-remote --heads origin <branch>` for remote collisions too; append `-2` suffix if needed.
4. Rename the branch to the conventional format (EnterWorktree sanitizes `/` to `+` and prepends `worktree-`):
   ```bash
   git branch -m "$(git branch --show-current)" "{TASK_TYPE}/{SLUG}"
   ```
5. Verify: `git branch --show-current`.

## Step 3: Implementation (TDD)

Follow the plan from Step 1 (or the resumed plan from the Issue). **If `RESUMING=true`**, start from item `NEXT_ITEM` — skip already-checked items.

For each unit of work (let `K` = the current plan item number), check the item's complexity label:

### 🔴 Complex items — Orchestrator implements directly

1. Write test first (TDD mandatory per CLAUDE.md). Skip for documentation-only or test-only items (mirrors the 🟢 branch's escape at the Sonnet prompt below).
2. Run targeted tests — confirm failure:
   ```bash
   source scripts/sim-dest.sh
   xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
     -destination "$DEST" -only-testing PasturaTests/<CurrentTestClass>
   ```
   Use `-only-testing` for the specific test class being developed — full suite per red/green cycle is too slow.
3. Write implementation.
4. Run targeted tests — confirm pass (same command as step 2).
5. Commit (Conventional Commits + emoji per CLAUDE.md).
6. **Sync checkpoint to GitHub Issue** — update the plan comment to check off the completed item:
   ```bash
   BODY=$(gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" --jq '.body')
   UPDATED=$(echo "$BODY" | sed "s/^- \[ \] ${K}\./- [x] ${K}./")
   gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" -X PATCH -f body="$UPDATED" --jq '.url'
   ```
   If `gh` fails, **warn and continue** — never block implementation on a sync failure.

### 🟢 Simple items — Delegate to Sonnet subagent

Launch a subagent via `Agent(model: "sonnet")` **without `isolation`** (shares the orchestrator's worktree). Subagents execute **sequentially, one at a time** — never in parallel. The subagent should have access to: `Read, Grep, Glob, Bash, Write, Edit` — do NOT include `EnterWorktree` or `ExitWorktree`.

Subagent invocation budget is governed by `.claude/rules/subagent-usage.md` — bound delegated items per its soft-budget heuristics so the subagent's investigation + final commit message fit the 32K output cap.

> **Agent prompt template:**
>
> "You are implementing item {K} of a plan for the Pastura iOS project.
>
> **IMPORTANT: Read `CLAUDE.md` first** — it contains all project conventions you must follow.
>
> Key rules (also in CLAUDE.md — read it for the full list):
> - No force unwrap (`!`) — use `guard let`, `if let`, or `?`
> - All types in Models/, LLM/, Engine/, Data/ MUST be marked `nonisolated` at the type level
> - Access modifiers: protocol definitions are `public`, types in Models/ are `public`, internal implementation uses default
> - Dependency rules: {include the relevant subset for the target layer}
> - Doc comments required on public protocols and types
>
> **Task:** {ITEM_DESCRIPTION}
> **Target file(s):** {PRIMARY_FILE_PATH} (and test file if applicable)
> **Reference:** {path to an existing similar file to follow as pattern, if applicable}
>
> **Procedure:**
> - If the task involves implementation changes, follow TDD:
>   1. Write the test first in `PasturaTests/`
>   2. Run the test — confirm it fails:
>      ```bash
>      source scripts/sim-dest.sh
>      xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
>        -destination "$DEST" -only-testing PasturaTests/{TestClass}
>      ```
>   3. Write the implementation
>   4. Run the test again — confirm it passes (same command)
> - If the task is documentation-only (doc comments) or test-only (no implementation needed), make the changes directly — skip TDD.
> - **Do NOT commit** — leave changes unstaged. The orchestrator will review and commit.
>
> If tests still fail after your best effort, return with a summary of what you tried and the error output."

**After the Sonnet subagent returns:**
1. Verify `git status` shows expected changes (no unexpected files).
2. Read the full diff (`git diff`) to understand the changes before composing the commit message.
3. Spot-check for obvious convention violations (nonisolated, access modifiers, dependency imports).
4. Commit (Conventional Commits + emoji per CLAUDE.md). The commit triggers the user approval gate.
5. Sync checkpoint to GitHub Issue (same `gh api` PATCH as the complex flow above).

**Fallback:** If the Sonnet subagent reports test failure (could not make tests pass), **Opus takes over immediately** — do not retry with Sonnet. Read the Sonnet error output to understand what was attempted. Then handle partial changes:
- Run `git stash -u` to save all of Sonnet's work including untracked new files (recoverable via `git stash pop` if needed later).
- Complete the item directly using the 🔴 complex-item flow.

Note: `git commit` is NOT in the permissions allowlist — each commit triggers user approval (intentional security gate).

After all implementation, run full verification directly from the main session:

1. Run the full test suite:
   ```bash
   source scripts/sim-dest.sh
   xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
     -destination "$DEST" 2>&1 | tail -80
   ```
   Pipe through `tail -80` to limit context window consumption. If failures need more detail,
   re-run with `-only-testing PasturaTests/<FailingTestClass>` for the specific class (no tail).

2. Handle the result:
   - **PASS** (`** TEST SUCCEEDED **`) → run `swiftlint lint --quiet --strict` directly. Fix any lint issues before proceeding.
   - **FAIL** (`** TEST FAILED **`) → fix the failing tests, verify the fix passes targeted tests locally, then commit with `🐛 fix:` prefix (no checkpoint sync needed — these are not plan items) and re-run the full suite.
   - **Hard limit: 3 iterations.** If still failing after 3, report remaining failures to the user and ask whether to proceed to Step 4.

## Step 4: Review — Gate G3

Launch a `code-reviewer` subagent via the Agent tool to review all changes on the feature branch. Pass `model: $REVIEWER_MODEL` (resolved from the plan's `## Metadata` — via Step 0 on resumption, or via Step 1 on a fresh run; defaults to Opus if absent). The Agent tool's `model` parameter takes precedence over the agent frontmatter's `model: opus`. The agent's checklist was enriched with a Pastura-specific trap cheat sheet in this same PR to keep the Sonnet-reviewer path safe.

```
Agent(subagent_type: "code-reviewer", model: "$REVIEWER_MODEL", description: "...", prompt: "...")
```

`$REVIEWER_MODEL` is the lowercase form (`opus` / `sonnet`) bound at Step 0 / Step 1 — the surrounding quotes match the Step 3 Sonnet-delegation convention (`Agent(model: "sonnet")`).

Subagent invocation budget is governed by `.claude/rules/subagent-usage.md` — large PR diffs may need splitting (per axis or per area) or Sonnet override (where the Coupling rule allows) to avoid `SCOPE_TOO_LARGE` early returns from the reviewer.

> **Agent prompt:** "Review all code changes on this feature branch. Run `git diff {DEFAULT_BRANCH}...HEAD` to see the full diff (all commits since branching, not just uncommitted changes). Read every changed file in full for context. Evaluate against your complete checklist (Hard Rules, Dependency Rules, Access Modifiers, Swift 6 Concurrency, Code Quality). Output your review in your standard format."

**Review-verify-fix loop:**
1. If the code-reviewer returns **PASS** → proceed directly to "Create PR?" gate.
2. If the code-reviewer returns **FAIL**:
   a. Launch 1 read-only verification agent to check each FAIL item for false positives (e.g., test code flagged for force unwrap, which is exempt).
   b. Build the **Review Action Summary** (see below) and present it to the user.
   c. Fix all confirmed issues. Skip false positives.
   d. Re-run the `code-reviewer` subagent on the updated code.
3. Hard limit: **3 iterations**. If still FAIL after 3, report remaining issues to the user.

**Review Action Summary** (displayed after each iteration):
```
## Review Iteration N

| # | Issue | Severity | Verification | Action | Reason |
|---|-------|----------|-------------|--------|--------|
| 1 | No doc comment on `FooProtocol` | Critical | Confirmed | Fixed | Added doc comment |
| 2 | Force unwrap in line 42 | Critical | False positive | Skipped | Test file (exempt) |
| 3 | Missing Sendable on `Bar` | Warning | Confirmed | Fixed | Added Sendable conformance |
```

Show the final review report. **Ask: "Create PR?"**

## Step 5: PR Creation — Gate G4

Derive base branch: `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`

Determine label from the commit prefix (TASK_TYPE or dominant commit type):

| Commit prefix | Label |
|---------------|-------|
| `feat` | `enhancement` |
| `fix` | `bug` |
| `docs` | `documentation` |
| `refactor` | `refactor` |
| `test` | `testing` |
| `chore` | `chore` |
| `ci` | `ci` |
| `perf` | `performance` |

Additionally, if the changes are security-related, add the `security` label alongside the prefix-based label.

Present PR draft (title + body + label) for user review:
- Title: Emoji prefix + Conventional format, under 70 chars (same emoji convention as CLAUDE.md commits)
- Body: Summary bullets + test plan + `Closes #N` (always present — Issue is always created)
- Label: from the table above

**Ask: "Create this PR?"**

```bash
gh pr create --base "$BASE_BRANCH" --assignee "@me" --label "$LABEL" \
  --title "..." --body "$(cat <<'IMPLEMENT_PR_BODY'
## Summary
...
## Test plan
...
IMPLEMENT_PR_BODY
)"
```

Push the branch first: `git push -u origin <branch>`. Then create the PR.

After creation:
- Print the PR URL.
- "Wait for all required status checks to pass, then **merge manually**."

## Step 6: Cleanup

**After merge** (guidance only — do NOT auto-execute):
1. `ExitWorktree` with action `"remove"`
2. `git checkout <default-branch> && git pull`
