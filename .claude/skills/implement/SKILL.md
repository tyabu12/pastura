---
name: implement
description: Orchestrate feature implementation from plan to PR — worktree isolation, TDD, review, and PR creation.
model: opus
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, EnterWorktree, ExitWorktree
argument-hint: "[description | issue-number | phase N]"
---

# /implement

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
   - Extract `TASK_TYPE` and branch name from the `## Metadata` section in the comment.
   - Derive `SLUG` from the branch name.
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
3. Format the plan as a numbered checkbox list (each item = one planned commit):
   ```
   - [ ] 1. <description> (`<primary-file-path>`)
   - [ ] 2. <description> (`<primary-file-path>`)
   ...
   ```
   Present this plan to the user. Store internally as `PLAN_BODY` for Issue attachment in Step 2.
4. **Ask: "Proceed with this plan?"** — For single-commit fixes, combine G1 and G2 into one confirmation.

## Step 1b: Plan Critique

After the user approves the plan (G1), launch a `critic` subagent via the Agent tool to review the plan for blind spots:

> **Agent prompt:** "Review the following implementation plan for the Pastura project. Focus on: scope creep beyond current phase, dependency rule violations in the planned file locations, missing edge cases, integration risks with existing modules, and assumptions not validated against the codebase.
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

Note: This is a conditional review step, not a numbered gate — the G1–G4 gate structure is unchanged.

## Step 2: Issue + Worktree — Gate G2

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
  PASTURA_PLAN
  )" --jq '.id')
  ```
  Set `ISSUE_NUMBER=N`.

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
4. Verify: `git branch --show-current`.

## Step 3: Implementation (TDD)

Follow the plan from Step 1 (or the resumed plan from the Issue). **If `RESUMING=true`**, start from item `NEXT_ITEM` — skip already-checked items.

For each unit of work (let `K` = the current plan item number):
1. Write test first (TDD mandatory per CLAUDE.md).
2. Run targeted tests — confirm failure:
   ```bash
   DEST='platform=iOS Simulator,name=iPhone 16'
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

Note: `git commit` is NOT in the permissions allowlist — each commit triggers user approval (intentional security gate).

SwiftLint runs automatically via PreToolUse hook on `git commit`.

After all implementation, run full verification using the `test-runner` subagent:

1. Launch a `test-runner` subagent via the Agent tool:

   > **Agent prompt:** "Run all tests for the Pastura project. Report results in your standard format including failure details."

   The test-runner runs in the background (per its agent definition). Wait for the completion notification before proceeding.

2. Handle the test-runner result:
   - **PASS** → run `swiftlint lint --quiet --strict` directly. Fix any lint issues before proceeding.
   - **FAIL** → fix the failing tests, verify the fix passes targeted tests locally, then commit with `🐛 fix:` prefix (no checkpoint sync needed — these are not plan items) and re-run the test-runner subagent for full suite.
   - **Hard limit: 3 iterations.** If still failing after 3, report remaining failures to the user and ask whether to proceed to Step 4.

## Step 4: Review — Gate G3

Launch a `code-reviewer` subagent via the Agent tool to review all changes on the feature branch:

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
- If unresolved after 3 iterations, present outstanding issues and let the user decide whether to proceed or continue fixing.

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
- Assignee: always `@me`

**Ask: "Create this PR?"**

Use HEREDOC with distinctive delimiter:
```bash
gh pr create --base "$BASE_BRANCH" --assignee "@me" --label "$LABEL" \
  --title "..." --body "$(cat <<'IMPLEMENT_PR_BODY'
## Summary
...
## Test plan
...
🤖 Generated with [Claude Code](https://claude.com/claude-code)
IMPLEMENT_PR_BODY
)"
```

Push the branch first: `git push -u origin <branch>`. Then create the PR.

After creation:
- Print the PR URL.
- "Wait for all required status checks to pass, then **merge manually**. Auto-merge is disabled."

## Step 6: Cleanup & Abandonment

**After merge** (guidance only — do NOT auto-execute):
1. `ExitWorktree` with action `"remove"`
2. `git checkout <default-branch> && git pull`
3. Remote branch: GitHub may auto-delete; if not, `git push origin --delete <branch>`

**To abandon** (no PR, or after PR created but want to cancel):
1. If PR exists: `gh pr close <number>`
2. `ExitWorktree` with action `"remove"`
3. If already pushed: `git push origin --delete <branch>`
