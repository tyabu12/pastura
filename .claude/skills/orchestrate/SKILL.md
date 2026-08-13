---
name: orchestrate
description: Orchestrate feature implementation from plan to PR — worktree isolation, TDD, review, and PR creation.
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, EnterWorktree, ExitWorktree
argument-hint: "[description | issue-number | phase N]"
---

<!-- generated-from: claude-kit skills/orchestrate-creator/orchestrate-template.md sha256:1fbc1aadc87e reconciled:2026-08-13 -->

# /orchestrate

Orchestrate the full development workflow: plan → issue → worktree → TDD implementation → review → PR.

> **Project-owned file, hand-reconciled against the claude-kit template — not generated from it.**
> This skill predates `/claude-kit:orchestrate-creator`; the stamp above records the template
> revision its content was last reconciled with (#1453), so a re-run reaches Step U-3's
> principle-level back-port proposals instead of stopping at U-1's "hand-written, report only".
> Edit this file freely — kit updates never touch it. `/claude-kit:orchestrate-creator` rewrites
> the stamp line on an upgrade, so anything that must survive belongs in the block below, not in it.
>
> **Read "up to date" narrowly.** Step U compares hashes first, so an unchanged template reports
> "up to date" — that means *no template change since the reconcile*, **not** that this file matches
> the template. It deliberately does not. Most divergences are additions, which an upgrade proposal
> cannot silently undo; these three are the ones a plausible-sounding back-port **would** undo:
>
> - **Step 1.3's "do not add a blanket 'when in doubt, go up a tier'" guardrail is not in the
>   template's Step 1** — it is a *negative* instruction, so nothing around it looks wrong once it is
>   gone, and it is the direct fix for the defect this file was reconciled to repair (#1453).
>   Reject any proposal to adopt the template's Step 1 wording that drops it.
> - **The Step 4 reviewer prompt omits the template's selective `.claude/rules/*.md` read** —
>   `.claude/agents/code-reviewer.md`'s Review Process step 3 owns that logic here. Do not add it in
>   both places; if that agent ever loses it, this prompt must gain it, or path-scoped review
>   coverage vanishes silently.
> - **The template's inlined subagent output-cap / split-budget note is omitted, and its "Project
>   parameters (baked at generation)" table has no counterpart** — `.claude/rules/subagent-usage.md`
>   is always-loaded here (inlining pays twice per turn, `.claude/rules/context-budget.md`), and this
>   file's parameters are inline at each step and richer than the table's cells.

## Constants

- `PLAN_MARKER`: `<!-- pastura-plan -->` — machine-readable marker embedded in Issue plan comments for detection during resumption.
- `OWNER_REPO`: derived at runtime via `gh repo view --json nameWithOwner -q '.nameWithOwner'`. Resolve early in Step 0 (before any `gh api` calls) — but **after** pre-flight check 1, which decides whether `gh` is usable at all; in degraded mode `OWNER_REPO` is unavailable and every `gh` step below is skipped.

## Step 0: Input Detection & Pre-flight

Interpret `$ARGUMENTS`:
- **`#N`** (digits after `#`): Fetch issue via `gh issue view N`, use title/body as task spec. Then check for an existing plan (see **Resumption Detection** below). In degraded mode (unauthenticated — see pre-flight check 1 below), `#N` cannot be fetched and resumption is unavailable; the task spec must come from the user inline instead.
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
   - Extract `SESSION_MODEL` from `## Metadata` the same way — normalize to lowercase (`opus` / `sonnet`) — and capture its `(reason: …)` tail as `SESSION_RATIONALE` for the Step 2b resume prompt. If `Session` is absent (older plan comment pre-dating this field), default `SESSION_MODEL=opus` (the safe fallback — orchestrator stays on Opus); `SESSION_RATIONALE` is then unused (the resume prompt is Sonnet-gated).
   - Derive `SLUG` from the branch name.
   - **Coupling re-check**: if the resumed plan contains any `🎭` item but `REVIEWER_MODEL=sonnet` **or** `SESSION_MODEL=sonnet` (e.g., from a post-plan Metadata edit that bypassed the Step 1 coupling rule), warn the user and offer to upgrade the affected model(s) to Opus before continuing — that is, before proceeding to Step 2 in the normal flow, or before the Step 4 review when all items are already complete. Reason: a 🎭 item is implemented by the orchestrator (session model) and must never run — or be reviewed — on Sonnet. When `SESSION_MODEL` resolves to (or is upgraded to) `opus`, ensure the running session is actually on Opus (`/model opus`) before resuming implementation.
   - **All-🎵 re-check**: the `any 🎭` predicate above cannot fire on an all-🎵 plan, but 🎵 does not certify simplicity — Step 1.3's tie-breaker also admits *specifiable but merely hard* items. So when the resumed plan is all 🎵 **and** `REVIEWER_MODEL=sonnet`, re-confirm each item is strictly within the 🎵 simple criteria (Step 1.4's independent test) and, if any is not, offer to upgrade `REVIEWER_MODEL` to Opus (the reviewer only — unlike the re-check above, which covers both models). `SESSION_MODEL=sonnet` stays — the cost lever survives an Opus reviewer.
   - If **all items are already checked**: do **not** silently proceed to review. A fully-checked *last* plan usually means its PR already merged — and on an **umbrella issue** that accumulates several historical plan comments, the `tail -1` in the resumption command above lands on that finished plan, so auto-proceeding would re-review completed work instead of planning the new work the user actually wants. Ask the user: "#N's last plan is complete (its PR likely merged) — resume-review it, or start a NEW plan for new work on #N?" Only ensure you are on the feature branch or in the correct worktree and **skip to Step 4** directly on an explicit "resume-review" answer; otherwise treat it as a fresh task and fall through to Step 1 (which then also runs Step 1b, since `RESUMING` no longer applies to this path).
   - Report to user: "Found existing plan on issue #N. {DONE}/{TOTAL} items complete. Resuming from item {NEXT_ITEM}."
   - **Skip Step 1 and Step 1b entirely** → proceed to Step 2.
3. If no plan comment found: proceed normally (Step 1 creates the plan, Step 2 attaches it).

**Pre-flight checks** (run in order):
1. `gh auth status` — if unauthenticated, run in **degraded mode**: no issue, no checkpoint sync, no resumption — and say so explicitly to the user rather than silently skipping. Skip all remaining `gh` steps; the plan lives only in-session.
2. `git status` — warn if uncommitted changes exist.
3. Verify on default branch (skip if `RESUMING=true`):
   - `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')` — this value still feeds Step 4's `git fetch origin {DEFAULT_BRANCH}`, `git rev-list … origin/{DEFAULT_BRANCH}`, and check 4's `git pull`, so degraded mode needs a fallback yielding a **bare branch name**, not a ref: `DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||')`. Plain `git symbolic-ref refs/remotes/origin/HEAD` returns `refs/remotes/origin/main` and `--short` alone returns `origin/main` — either shape breaks every consumer above except the two `diff {DEFAULT_BRANCH}...HEAD` uses, which accept a full ref by luck. If `origin/HEAD` is unset (common in a fresh clone), recover with `git remote set-head origin -a`.
   - If current branch != `DEFAULT_BRANCH`, warn and offer `git switch "$DEFAULT_BRANCH"`.
4. `git pull --ff-only origin "$DEFAULT_BRANCH"` — warn on failure, don't block. Skip if `RESUMING=true`.
5. If already in a worktree, warn and suggest `ExitWorktree` first (unless `RESUMING=true` and the worktree matches the expected branch).

## Step 1: Plan — Gate G1

1. Read `CLAUDE.md` for current phase and conventions.
2. If phase-related, read ONLY the relevant Phase section from `docs/ROADMAP.md`.
3. Format the plan as a numbered checkbox list (each item = one planned commit).
   Assign a **complexity label** to each item — the icon matches the model tier that implements it (🎵 Sonnet subagent, 🎭 Opus session):
   - 🎵 **simple** — Delegated to a Sonnet subagent. Criteria: existing pattern reuse (e.g., new Handler mirroring an existing one), test-only changes following an existing test pattern, type/error case additions, doc comments, minor fixes.
   - 🎭 **complex** — Implemented by the orchestrator (session model) directly. Criteria: new design patterns, actor isolation / Sendable design decisions, changes spanning multiple layers, work near dependency rule boundaries (Engine ↔ Data), or any item requiring non-obvious architectural judgment.
   - **The 🎭 criteria win outright.** They name the *nature* of the work, not its difficulty, so an item matching one stays 🎭 however settled its spec is. The tie-breaker resolves only items matching neither list.
   - **Tie-breaker — is it fully specifiable?** Not "too hard for Sonnet?": difficulty or size alone does not promote an item. A 🎵 subagent inherits none of this conversation, so ask: can you fill the Step 3 🎵 prompt slots *now* without a new design decision — target file(s), plus an existing pattern to mirror or an acceptance condition? **Yes, even if hard → 🎵.** No, or you can't tell whether the slots are fillable → 🎭 (that specific uncertainty — not general unease). Also promote a 🎵 to 🎭 when subagent prompt + verify overhead exceeds the implementation itself — single-line edits, short doc tweaks; that promotion forces an Opus reviewer via the Coupling rule below, which is intended since the orchestrator implements the item directly.
   - **Do not add a blanket "when in doubt, go up a tier."** It was removed deliberately: Claude 5 applies such a booster literally, so it fires far harder than it was tuned for and cancels Step 1.5's cost lever. Promotion must name its trigger — a 🎭 criterion, an unfillable prompt slot, or the overhead clause — never a bare feeling of unease.

   ```
   - [ ] 1. 🎵 <description> (`<primary-file-path>`)
   - [ ] 2. 🎭 <description> (`<primary-file-path>`)
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
   - Database schema migrations (`Data/DatabaseManager+Migrations.swift`) — a defect here corrupts existing users' data irreversibly, and no test on a fresh database reaches it
   - Integrity / crypto surfaces (`App/ReplayHashing.swift`, the model SHA-256 verification in `App/ModelManager.swift`) — a weakened check fails open, silently accepting a corrupt or substituted GGUF
   - LLM backend code or prompt templates
   - Design system foundations (`docs/design/design-system.md`, `DesignTokens*.swift`)

   **Sonnet reviewer acceptable** — the change must be strictly a subset of the 🎵 simple-item criteria above (existing pattern reuse, test-only changes following an existing pattern, type/error case additions, doc comments, minor fixes), AND none of the items match the Opus-required list. **Test that independently — a 🎵 label does not certify it.** The Step 1.3 tie-breaker also routes *specifiable but merely hard* items to 🎵, and those are not strictly simple: if the plan has one, the reviewer is Opus. Keep `Session: Sonnet` there — the cost lever survives an Opus reviewer. Concretely, the most common Sonnet-acceptable shapes are:
   - New `@Test` cases in an **existing** suite following the file's existing pattern (not new suites, new helpers, or trait changes like `.timeLimit` / `.serialized`)
   - Documentation updates (`docs/ROADMAP.md`, `docs/examples/**`, `docs/gallery/**`, `docs/prototype/**`, doc comments)
   - Simple refactor within a single file without crossing layer boundaries
   - Design token **application** (existing token to existing View only — new token additions are Opus-required)
   - Fix-only PRs where the cause is already diagnosed and localized

   **Coupling rule:** If **any** plan item is labeled 🎭, the reviewer MUST be Opus — even if the target paths look Sonnet-eligible. This prevents the "all-🎵-plus-Sonnet-reviewer" configuration from putting orchestrator-implemented work through a Sonnet review.

   The subtle convention traps that used to justify a blanket "when in doubt, pick Opus" here (ShapeStyle+Color tokens, `nonisolated` gaps, i18n `String(localized:)` omissions, missing `@Suite(.timeLimit(.minutes(1)))`) are carried by `.claude/agents/code-reviewer.md`'s trap cheat sheet and the always-loaded `.claude/rules/swift-isolation.md`, which reach the reviewer at either tier. Their absence from this section is deliberate — the three rules above are what decides the tier.

   Record the decision in the `## Metadata` block of the plan comment (see Step 2a) as:
   ```
   - **Reviewer**: Opus (reason: touches Engine/ dependency boundary)
   ```
   Store the rationale string as `REVIEWER_RATIONALE` (the `(reason: ...)` tail) for use in the Step 2a template. The user may override at G1. Resumed sessions recover the decision from `## Metadata` (see Step 0).
5. **Assign a session model** for the implementation phase (Step 3 onward). This is the model the orchestrator itself runs as — the user switches it manually via `/model` at G2 (or the combined single-commit gate), since the orchestrator cannot change its own session model. Derivation is **label-driven only** (unlike the reviewer, which also has path-based Opus triggers):

   - **Any plan item labeled 🎭** → `Session`: **Opus**. The orchestrator implements 🎭 items directly — the judgment-heavy work that needs the Opus tier.
   - **All items 🎵** → `Session`: **Sonnet** (recommended). The orchestrator's remaining work is dispatch, diff spot-check, commit, and PR mechanics. This is the primary cost lever: the long implementation tail runs at Sonnet rates.

   **Why review quality is unaffected:** the reviewer is assigned independently of the *session model* — not of the label, which Step 1.4 tests separately. The Step 1b critic runs at Opus (`claude-kit:critic` carries no model pin, so Step 1b passes `model: opus` explicitly — no override), and the Step 4 `code-reviewer` runs at `REVIEWER_MODEL` (which the path-based Coupling rule already forces to Opus on sensitive paths). A Sonnet session changes who *dispatches and commits*, not who *reviews*.

   **Accepted risk (all-🎵 on a Sonnet-eligible path):** when both session and reviewer are Sonnet, the pre-commit spot-check at Step 3 🎵 also runs on Sonnet — no Opus touches the tail except the pre-code Step 1b critic. What licenses that is **Step 1.4's strictly-simple test having passed independently**, not the 🎵 labels: an item that reached 🎵 via the *merely hard* tie-breaker has already floored the reviewer at Opus, so this configuration is unreachable for it. G1 remains the human gate — bump `Session` to Opus if a sensitive-but-🎵 change warrants it.

   Record in `## Metadata` (Step 2a) as `- **Session**: Sonnet (reason: all items 🎵)`, and store the rationale tail as `SESSION_RATIONALE`. **`effort` is not recorded** — it stays at the session default (`high`) per operator convention; model is the cost lever, not effort. Resumed sessions recover the decision from `## Metadata` (see Step 0).

   **Override constraint (Coupling):** the user may override `Session` at G1, but **a Sonnet override is rejected when any item is 🎭** — warn and keep Opus. A 🎭 item is implemented by the orchestrator directly, which must be at the Opus tier. (Mirrors the reviewer Coupling rule; re-checked on resume — see Step 0.)
6. **Ask: "Proceed with this plan, reviewer-model, and session-model choice?"** — present the plan checkboxes plus the proposed `Reviewer:` and `Session:` decisions so the user can override either at G1. For single-commit changes, combine G1 and G2 into one confirmation, but still run Step 1b (critic review) before creating the worktree; when the combined gate applies and `Session: Sonnet`, surface the `/model sonnet` recommendation at that same confirmation (after the critic, which stays on Opus).

After user approval, proceed to Step 1b (mandatory critic review).

## Step 1b: Plan Critique (REQUIRED)

This step is a review gate: complete it before Step 2. Skipped only when `RESUMING=true`.

After the user approves the plan (G1), launch a `claude-kit:critic` subagent via the Agent tool to review the plan for blind spots. The agent comes from the claude-kit plugin (`enabledPlugins` in `.claude/settings.json` — Pastura keeps no local copy); it carries no model pin, so **pass `model: opus` explicitly** at invocation. If the agent type is unavailable (plugin not yet trusted/installed on this machine), stop and surface that instead of silently skipping the critique.

```
Agent(subagent_type: "claude-kit:critic", model: "opus", description: "...", prompt: "...")
```

The literal block (mirroring Step 4) makes the Opus pin mechanical rather than prose-recalled — an omitted `model` would silently inherit a Sonnet session (the all-🎵 lever, Step 1) and downgrade this mandatory gate.

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

**Degraded mode (unauthenticated):**
- Skip issue creation and plan attachment; keep the plan in-session (no resumption).

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
  - **Session**: {SESSION_MODEL} (reason: {SESSION_RATIONALE})
  PASTURA_PLAN
  )" --jq '.id')
  ```
  Set `ISSUE_NUMBER=N`. When emitting `{REVIEWER_MODEL}` and `{SESSION_MODEL}` into Metadata, title-case the values (`Opus` / `Sonnet`) for readability — Step 0's parser normalizes back to lowercase on read.

**Otherwise** (new task — create an issue whenever authenticated, because checkpoint sync and resumption require a `COMMENT_ID` on a real Issue; in degraded mode this step is already skipped above):
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
  **Label fallback:** if `--label "$LABEL"` fails (the label doesn't exist in the repo), retry the command without `--label` (or offer to create the label first) — never block issue creation on a missing label.
- Post the plan as the first comment (same format as the `#N` case above). **Capture `COMMENT_ID` from the response** (`--jq '.id'`) — it is required for checkpoint sync in Step 3.

### 2b: Worktree Setup

**If `RESUMING=true`**:
1. Check for existing worktree: `git worktree list | grep {SLUG}`.
2. If found → `EnterWorktree` with the existing worktree name.
3. If not found but branch exists remotely → fetch the branch and create a new worktree from it.
4. If nothing exists → create a new worktree (normal flow).
5. **If `SESSION_MODEL=sonnet`**, prompt the user to switch first: "This plan recommends a **Sonnet** session ({SESSION_RATIONALE}). Run `/model sonnet` now, then confirm." Then **Ask: "Resume from item {NEXT_ITEM}/{TOTAL}?"**

**Otherwise** (normal flow):
1. Display: "Issue #{ISSUE_NUMBER} created. Branch: `{TASK_TYPE}/{SLUG}`"
2. **If `SESSION_MODEL=sonnet`**, tell the user to switch before implementation begins: "Session recommendation: **Sonnet** ({SESSION_RATIONALE}). Run `/model sonnet` now (or keep Opus by ignoring), then confirm below." Then **Ask: "Create worktree and start?"**
3. Call `EnterWorktree` with `name: "{TASK_TYPE}/{SLUG}"`.
   - On failure: suggest alternative name or cleanup. Check `git ls-remote --heads origin <branch>` for remote collisions too; append `-2` suffix if needed.
4. Rename the branch to the conventional format (EnterWorktree sanitizes `/` to `+` and prepends `worktree-`):
   ```bash
   git branch -m "$(git branch --show-current)" "{TASK_TYPE}/{SLUG}"
   ```
5. Verify: `git branch --show-current`.
6. **Worktree path hygiene** (holds for the rest of the session): the main checkout at `/Users/tyabu12/Work/pastura` stays on another branch, so a tool that resolves to it instead of this worktree acts on the wrong tree silently.
   - Every absolute Edit/Write path must contain `/worktrees/<name>/` — invalidate any carried over from a *pre-worktree* tool result before reusing it.
   - Non-isolation subagents (Step 3 `implementer`, Step 4 reviewer) inherit this worktree's cwd — but cwd inheritance for a non-isolation subagent is **not documented as guaranteed**, and it has resolved to the *original* checkout in practice, yielding an empty phantom diff that reads as a false FAIL. So don't rely on it: capture the root once with `WORKTREE_ROOT=$(git rev-parse --show-toplevel)` and **embed `git -C {WORKTREE_ROOT}`** into every subagent prompt that runs git — never a bare `git` the subagent resolves against its own cwd, never a `$(…)` it re-runs, and never a reused pre-worktree path.

## Step 3: Implementation (TDD)

Follow the plan from Step 1 (or the resumed plan from the Issue). **If `RESUMING=true`**, start from item `NEXT_ITEM` — skip already-checked items.

For each unit of work (let `K` = the current plan item number), check the item's complexity label:

> **Per-item commit hazard:** the pre-commit `swiftlint --strict` lints the **whole worktree**, not just the staged set — so an unstaged edit to a *later* item's file (e.g. one that trips a length cap) fails the *current* item's commit. Don't pre-edit a later item while committing the current one; if unavoidable, `git stash push -- <later-item-files>` before the focused commit, then pop.

### 🎭 Complex items — Orchestrator implements directly

1. Write test first (TDD mandatory per CLAUDE.md). Skip for documentation-only or test-only items (mirrors the 🎵 branch's escape at the Sonnet prompt below).
2. Run targeted tests — confirm failure:
   ```bash
   scripts/xcodebuild.sh test -only-testing PasturaTests/<CurrentTestClass>
   ```
   Run from the repo root — the wrapper supplies `-scheme` / `-project` / `-destination` / `-derivedDataPath` and the simulator gate internally (see `.claude/rules/xcodebuild-cli.md`). Use `-only-testing` for the specific test class being developed — full suite per red/green cycle is too slow.
3. Write implementation.
4. Run targeted tests — confirm pass (same command as step 2).
5. Commit (Conventional Commits + emoji per CLAUDE.md).
6. **Sync checkpoint to GitHub Issue** (skip in degraded mode) — update the plan comment to check off the completed item:
   ```bash
   BODY=$(gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" --jq '.body')
   UPDATED=$(echo "$BODY" | sed "s/^- \[ \] ${K}\./- [x] ${K}./")
   gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" -X PATCH -f body="$UPDATED" --jq '.url'
   ```
   If `gh` fails, **warn and continue** — never block implementation on a sync failure.

### 🎵 Simple items — Delegate to Sonnet subagent

Launch a subagent via `Agent(model: "sonnet")` **without `isolation`** (shares the orchestrator's worktree). Subagents execute **sequentially, one at a time** — never in parallel. The subagent should have access to: `Read, Grep, Glob, Bash, Write, Edit` — do NOT include `EnterWorktree` or `ExitWorktree`.

Subagent invocation budget is governed by `.claude/rules/subagent-usage.md` — bound delegated items per its soft-budget heuristics.

> **Agent prompt template:**
>
> "You are implementing item {K} of a plan for the Pastura iOS project.
>
> Work inside `{WORKTREE_ROOT}` — treat every path in this prompt as rooted there; do not rely on inherited cwd.
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
>   2. Run the test — confirm it fails (from the repo root; the wrapper supplies scheme / destination / DerivedData internally):
>      ```bash
>      scripts/xcodebuild.sh test -only-testing PasturaTests/{TestClass}
>      ```
>   3. Write the implementation
>   4. Run the test again — confirm it passes (same command)
> - If the task is documentation-only (doc comments) or test-only (no implementation needed), make the changes directly — skip TDD.
> - **Do NOT commit** — leave changes unstaged. The orchestrator will review and commit.
>
> If tests still fail after your best effort, return with a summary of what you tried and the error output."

**`-C {WORKTREE_ROOT}` applies to `git` only** — `scripts/xcodebuild.sh` invocations inside the prompt above must stay a **bare, cwd-relative** command. Reason, per `.claude/rules/xcodebuild-cli.md` § "Canonical invocation": a `cd … &&` prefix, an absolute path, or a leading env-var assignment misses the allowlist entry and stalls the delegated subagent on an approval prompt, and the wrapper has no `-C` — it resolves `REPO_ROOT` internally. **Do not generalize that into a claim about how the matcher works**: the git allowlist entries are equally bare (`Bash(git diff*)`, …), yet `git -C <path> diff` has been observed to run unprompted, so the two are not the same case and only the xcodebuild one is measured.

> **Residual risk this carve-out does not close.** Because the wrapper resolves `REPO_ROOT` from cwd, a subagent whose cwd landed in the main checkout — the very failure the `-C` mandate exists for — builds and tests **that** tree and returns `** TEST SUCCEEDED **` on unrelated code. Unlike the phantom-diff case, this one reads as success. The path-rooting sentence in the prompt is a soft instruction, not a guarantee, so before trusting a delegated green, confirm the subagent worked here: have it report `pwd`, or compare `git -C {WORKTREE_ROOT} status` against what it claims to have changed. The main-session full-suite re-run at the end of Step 3 is the backstop.

**After the Sonnet subagent returns:**
1. Verify `git status` shows expected changes (no unexpected files).
2. Read the full diff (`git diff`) to understand the changes before composing the commit message.
3. Spot-check for obvious convention violations (nonisolated, access modifiers, dependency imports).
4. Commit (Conventional Commits + emoji per CLAUDE.md). `git commit` is allowlisted; the commit-time gate is the git pre-commit hook (`swiftlint --strict` + build), not a per-commit approval prompt.
5. Sync checkpoint to GitHub Issue (same `gh api` PATCH as the complex flow above; skip in degraded mode).

**Fallback:** If the Sonnet subagent reports test failure (could not make tests pass), **take over immediately** — do not retry with Sonnet. Read the Sonnet error output to understand what was attempted, then:
1. Run `git stash -u` to save all of Sonnet's partial work including untracked new files (recoverable via `git stash pop` if needed later), giving the recovery a clean start.
2. **Escalate by session model:**
   - `SESSION_MODEL=opus` → the orchestrator completes the item directly using the 🎭 complex-item flow.
   - `SESSION_MODEL=sonnet` → the orchestrator is itself Sonnet, so it must **not** implement judgment-heavy recovery. Delegate to `Agent(subagent_type: "implementer", model: "opus")` **without `isolation`** (shares the worktree), passing the item spec, the Sonnet subagent's error output, **and the same `{WORKTREE_ROOT}` rooting the 🎵 prompt carries** — this is the subagent that writes files, so an inherited cwd landing in the main checkout is the worst case, not the mildest. On return, the orchestrator reviews the diff and commits (same as the 🎵 post-return flow above). If the Opus implementer also fails, report to the user and offer to switch the session to Opus (`/model opus`) and retry directly. (`implementer` pins `effort: medium`; if recovery underperforms, note it and escalate to a high-effort general Opus subagent.)

Note: `git commit` is allowlisted (since #411); the commit-time gate is the git pre-commit hook (`swiftlint --strict` + build + blocklist/gallery gates per CLAUDE.md), which runs on every commit — not a per-commit approval prompt.

After all implementation, run full verification directly from the main session:

1. Run the full test suite:
   ```bash
   scripts/xcodebuild.sh test --tail 80
   ```
   `--tail 80` is the wrapper's pipefail-safe output cap — do NOT use external `| tail`, which
   masks failed builds as exit 0 (see `.claude/rules/xcodebuild-cli.md`). If failures need more
   detail, re-run with `-only-testing PasturaTests/<FailingTestClass>` for the specific class (no `--tail`).

2. Handle the result:
   - **PASS** (`** TEST SUCCEEDED **`) → run `swiftlint lint --quiet --strict` directly. Fix any lint issues before proceeding.
   - **FAIL** (`** TEST FAILED **`) → fix the failing tests, verify the fix passes targeted tests locally, then commit with `🐛 fix:` prefix (no checkpoint sync needed — these are not plan items) and re-run the full suite.
   - **Hard limit: 3 iterations.** If still failing after 3, report remaining failures to the user and ask whether to proceed to Step 4.

> **Carve-out — build-irrelevant branches:** the predicate for skipping the full run above is not a
> judgement call — it is `scripts/precommit-gate-classify.sh` (read its header doc-comment before
> relying on this). Feed it the branch's changed paths, not just the last commit's — the script
> reads whatever set it's given, so for a whole branch pipe
> `git -C {WORKTREE_ROOT} diff --name-only {DEFAULT_BRANCH}...HEAD` into
> `scripts/precommit-gate-classify.sh` (cwd-relative; unlike the wrapper it is **not** allowlisted,
> so expect one approval prompt). No `build` token in its output means every changed path
> matched its build-irrelevant denylist, so the app target is never compiled and the suite cannot be
> affected — skip step 1 entirely. No `lint` token means the same for step 2's
> `swiftlint lint --quiet --strict`. The obvious justification — that CI provides a backstop
> against a bad skip — does not hold: `.github/workflows/ci.yml` reuses this same script for its
> PR path-gating, so a build-irrelevant PR skips `lint-and-test` and `ui-test` on CI too. The
> safety instead comes from two other things: the script is **conservative by inversion** (it
> skips only when *every* path matches a small denylist; any unrecognized path forces `build`),
> and a push to `{DEFAULT_BRANCH}` always runs the full iOS suite regardless of paths (CI
> short-circuits every non-`pull_request` event to `ios=true`), so the post-merge state stays
> covered. When skipping, state the one-line reason in the PR body (Step 5).

## Step 4: Review — Gate G3

**Before launching the reviewer,** `git fetch origin {DEFAULT_BRANCH}` and check `git rev-list --count HEAD..origin/{DEFAULT_BRANCH}` — a long session (research → critic → multi-commit implementation) can span hours during which `{DEFAULT_BRANCH}` advances. If the count is non-zero, offer a rebase before review; **mandatory** when the diff touches large generated / data files (xcstrings, lockfiles), where a rebase or non-conflicting auto-merge can drop upstream entries without surfacing a conflict.

Launch a `code-reviewer` subagent via the Agent tool to review all changes on the feature branch. Pass `model: $REVIEWER_MODEL` (resolved from the plan's `## Metadata` — via Step 0 on resumption, or via Step 1 on a fresh run; defaults to Opus if absent). The Agent tool's `model` parameter takes precedence over the agent frontmatter's `model: opus`. The agent's checklist carries a Pastura-specific trap cheat sheet to keep the Sonnet-reviewer path safe. The reviewer **MUST emit** a `**Verdict**: PASS | FAIL` line — the review-verify-fix loop below parses it, and a reviewer that omits it breaks the gate.

```
Agent(subagent_type: "code-reviewer", model: "$REVIEWER_MODEL", description: "...", prompt: "...")
```

`$REVIEWER_MODEL` is the lowercase form (`opus` / `sonnet`) bound at Step 0 / Step 1 — the surrounding quotes match the Step 3 Sonnet-delegation convention (`Agent(model: "sonnet")`).

Subagent invocation budget is governed by `.claude/rules/subagent-usage.md` — large PR diffs may need splitting (per axis or per area) to avoid `SCOPE_TOO_LARGE` early returns from the reviewer. **Splitting is the only remedy** — a cheaper model buys no headroom (§3 there), so never downgrade `REVIEWER_MODEL` to fit a diff.

> **Agent prompt:** "Review all code changes on this feature branch. Run **`git -C {WORKTREE_ROOT} diff {DEFAULT_BRANCH}...HEAD`** for the full diff (all commits since branching, not just uncommitted changes) — use the `-C` path, not cwd; a bare `git` can resolve to the original checkout and show an empty phantom diff. Read every changed file in full for context. Evaluate against your complete checklist (Hard Rules, Dependency Rules, Access Modifiers, Swift 6 Concurrency, Code Quality). Output your review in your standard format."

**Review-verify-fix loop:**
1. If the code-reviewer returns **PASS** → proceed directly to Step 5 (PR creation).
2. If the code-reviewer returns **FAIL**:
   a. Launch 1 read-only verification agent to check each FAIL item for false positives (e.g., test code flagged for force unwrap, which is exempt). Root its prompt at `{WORKTREE_ROOT}` and give it `git -C {WORKTREE_ROOT}` like any other subagent — the mandate in Step 2b binds every prompt the orchestrator composes, including ad-hoc ones with no template here.
   b. Build the **Review Action Summary** (see below) and present it to the user.
   c. Capture `FIX_BASE=$(git rev-parse HEAD)`, then fix all confirmed issues. Skip false positives.
   d. Re-run the `code-reviewer` subagent **scoped to the fix diff**: prompt it with `git -C {WORKTREE_ROOT} diff {FIX_BASE}...HEAD` (the fix commits only — same `-C` rule as the first-pass prompt) plus the prior FAIL items, instructing it to verify each fix and its immediate blast radius — NOT to re-review the full branch. Fall back to a full-branch re-review only when the fixes touched files outside the set reviewed in the previous iteration.
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

Show the final review report, then proceed to Step 5 (PR creation).

## Step 5: PR Creation

**Degraded mode:** skip PR creation entirely — report that the branch is ready to push / PR manually, and stop.

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

**Determine device-QA need.** Manual on-device QA is required when the diff touches a surface the iOS Simulator build cannot exercise:
- `#if !targetEnvironment(simulator)` blocks (e.g. `SettingsView` model-management UI, `ModelSettingsRow`) — excluded from the simulator build entirely.
- Metal / llama.cpp on-device inference (`LlamaCppService`, GGUF model load, GPU paths).
- Layout / visual regressions inside those device-only blocks (the simulator never renders them).
- Pattern-6 executor-inheritance UI freezes (`.claude/rules/swift-isolation.md`) — reproduce only on a real device.

Config / docs / shell / test-only changes with no such surface do **not** need device QA.

Present the PR draft (title + body + label) for visibility — this is informational; the PR is created automatically, with no confirmation gate:
- Title: Emoji prefix + Conventional format, under 70 chars (same emoji convention as CLAUDE.md commits)
- Body: Summary bullets + test plan + a `## Device QA` section + an issue reference (omit the issue reference in degraded mode — there is no issue). Use `Closes #N` only when this PR completes the issue; for a non-final PR of a multi-PR or umbrella issue, use `Part of #N` instead so merging it does not prematurely auto-close the issue (see CLAUDE.md § "Git Conventions" → "Closing issues in multi-PR splits"). The `## Device QA` section lists the concrete on-device steps a reviewer must run, or a single `実機QA不要` line with the one-line reason when none apply.
- Label: from the table above

Push the branch first as its **own** Bash tool call: `git push -u origin <branch>`. Then create the PR as a **separate** call — never combine the two with `&&`, or the `gh pr create --base`-gated PreToolUse (`check-claude-md`) and PostToolUse (`pr-created-reflection`) hooks won't fire (their prefix gate is anchored at position 0, so a leading `git push` breaks the match):

```bash
gh pr create --base "$BASE_BRANCH" --assignee "@me" --label "$LABEL" \
  --title "..." --body "$(cat <<'IMPLEMENT_PR_BODY'
## Summary
...
## Test plan
...
## Device QA
<concrete on-device steps, or `実機QA不要` + one-line reason>
IMPLEMENT_PR_BODY
)"
```

**Label fallback:** if `--label "$LABEL"` fails (the label doesn't exist in the repo), retry the command without `--label` (or offer to create the label first) — never block PR creation on a missing label.

After creation:
- Print the PR URL.
- "Wait for all required status checks to pass, then **merge manually**."

## Step 6: Cleanup

**After merge** (guidance only — do NOT auto-execute):
1. `ExitWorktree` with action `"remove"`
2. `git switch <default-branch> && git pull`

> **Post-merge `remove` may refuse:** squash / rebase merge gives the merged commit a **new SHA**, so the worktree's local commits read as unmerged by ancestry and `ExitWorktree(action: "remove")` refuses — as it also can *before* the post-merge `pull`, when local `main` doesn't yet contain the merge. Once the user confirms the merge landed, re-invoke with `discard_changes: true`. (Pastura defaults to squash, so a post-merge `remove` refuses by default.)
