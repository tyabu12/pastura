---
name: queue-consumer
description: Consume agent-ready GitHub issues into Draft PRs — one overnight queue run. Fetches open agent-ready issues oldest-first, implements each on an agent/issue-<N> branch, tests, passes a mandatory code review, opens a Draft PR, and appends the run digest. Use when the user asks to run the issue queue, consume agent-ready issues, process the overnight queue, work through queued agent tasks, or run the queue consumer.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
---

# /queue-consumer

One overnight queue run: **fetch → check → implement → review → Draft PR
→ digest**. Run from the repository root of the current checkout — the
skill is designed to run inside the routine-provided worktree and never
calls EnterWorktree (nested worktree creation is rejected); per-issue
isolation comes from plain branches created off `origin/main`.

This skill is bound by the brush-up family's shared **Output Contract**.
**Canonical text: `.claude/rules/automation-output-contract.md` — read it in
full before Step 0.** It is path-scoped to `.claude/skills/**`, which fires on a
skill *edit*, not on this skill's *execution*; nothing auto-loads it during a
run. Because this generator writes **arbitrary code**, it is the one explicitly
excluded from the contract's "auto-fix PRs may skip a code-review pass"
exemption — the mandatory `code-reviewer` gate below is that exclusion in
operational form.

Non-goals:

- **No scheduled execution.** Invocation is manual or via the nightly
  routine; the skill never registers itself.
- **No merging, no issue closing.** The morning human reviews each Draft
  PR; merging closes the issue (`Closes #N`).
- **No cross-repo work, no parallelism.** Issues are processed one at a
  time in this repository only.

## Constants

- `QUOTA`: 2 attempted issues per run (completed + implementation-blocked;
  pre-start skips do not count)
- Branch: `agent/issue-<N>`; collision fallback `agent/issue-<N>-<YYYYMMDD>`
- Labels: `agent-ready` (input — human-assigned only), `needs-detail`,
  `agent-blocked`
- Digest: `data/queue/digest.md` — a gitignored **local log** in the main
  checkout (the helper script resolves it; the worktree's copy would die
  with the worktree, and it bootstraps the file if absent)
- Helper scripts: `.claude/skills/queue-consumer/scripts/`

## Hard rules (non-negotiable)

1. **Never push to main. Never force push.** All pushes are
   `git push -u origin agent/...`. A PreToolUse guard hook additionally
   blocks `--force` shapes and `gh pr ready` — do not try to work around
   it; prefix allowlists cannot forbid suffixes, so the hook and this
   rule are the only guards.
2. **Never close an issue.** Closing happens through the human's merge.
3. **PRs are always Draft.** Never run `gh pr ready`. `--draft` must be
   the first flag of `gh pr create` (the permission allowlist pins the
   literal prefix `gh pr create --draft`).
4. **Max 1 retry per issue.** After a failed attempt, retry once from a
   clean branch; if that also fails, swap labels to `agent-blocked`,
   comment the reason, and move on. Never burn the night on one issue.
5. **Acceptance criteria bound the change.** Implement the minimum that
   satisfies them. `### Out of scope` is binding. No "while at it"
   changes, even obvious ones — note them in the PR body instead.
6. **No unreviewed PR.** If the code-reviewer pass is missing, returns
   `SCOPE_TOO_LARGE`, or looks truncated (no final verdict), do NOT open
   the PR — treat the issue as blocked with that reason.

## Step 0 — Preflight (abort the run on any failure)

1. `gh auth status` succeeds.
2. The three labels exist: `gh label list` contains `agent-ready`,
   `needs-detail`, `agent-blocked`.
3. The frozen interface exists on main:
   `git cat-file -e origin/main:.github/ISSUE_TEMPLATE/agent-task.yml`
   (the form whose rendered `### Acceptance criteria` /
   `### Out of scope` headings this skill parses — see #528).
4. `git fetch origin main` (branches are cut from `origin/main`, not the
   possibly-stale local `main`).
5. Working tree is clean (`git status --porcelain` empty) — a dirty
   routine worktree means a previous run died mid-issue; abort and
   report rather than contaminating a new branch.
6. **Read `.claude/rules/automation-output-contract.md` in full.** Abort if
   missing. It does not auto-load during a run (its `paths:` glob fires on
   a skill edit), so this is the only step that puts the contract in
   context — and this generator writes arbitrary code, so it is the one
   the contract binds hardest.

## Step 0.5 — WIP backpressure (skip when the review queue is saturated)

The family's aggregate ceiling, on top of this skill's own `QUOTA` (≤2
attempted issues per run): `QUOTA` bounds *this* skill's lane, the ceiling
bounds the *sum* of unreviewed Drafts across all generators.

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

## Step 1 — Fetch the queue

```bash
gh issue list --label agent-ready --state open \
  --json number,title,createdAt --jq 'sort_by(.createdAt)'
```

Process oldest-first. Stop when `QUOTA` issues have been attempted or
the queue is exhausted, then go to Step 6.

## Step 2 — Per-issue pre-start checks (skips do NOT consume quota)

Read the issue: `gh issue view <N> --json title,body,labels`.

**a. Already in flight** — an open PR whose head is exactly
`agent/issue-<N>` or starts with `agent/issue-<N>-` (datestamp fallback;
match exact-or-dash so issue-1 does not match issue-12):

```bash
gh pr list --state open --json headRefName,url \
  --jq '[.[] | select(.headRefName == "agent/issue-<N>" or (.headRefName | startswith("agent/issue-<N>-")))]'
```

Non-empty → record `skipped (PR already open)` and continue. The
previous night's work is awaiting human review; do not duplicate it.

**b. Acceptance criteria present and concrete** — machine predicate
first: the body contains a `### Acceptance criteria` heading with at
least one `- [ ]` item. Then judge each item: could a reviewer verify it
objectively against the diff or a test? Vague items ("improve UX",
"make it faster") fail. On failure:

```bash
gh issue edit <N> --remove-label agent-ready --add-label needs-detail
gh issue comment <N> --body "..."   # list concretely what is missing
```

Record `skipped (needs-detail)`. **When in doubt, needs-detail** — a
wrong skip costs one human relabel; a wrong attempt costs a bad PR.

**c. Unattended-safe** — block (don't attempt) issues an unattended
agent must not decide alone. Criteria, not a path list:

- CLAUDE.md reserves the decision for the user: new SPM dependencies,
  public protocol signature changes, significant design changes / ADRs.
- The change lands on judgment-heavy surfaces the orchestrate coupling
  rule marks Opus-required *because they need human-in-the-loop trade-offs*:
  project tooling (`.claude/**`, `CLAUDE.md`, CI workflows),
  AppRouter / navigation structure, dependency-rule boundaries
  (Engine ↔ Data), content-safety surface, `docs/decisions/**`.

On match: swap to `agent-blocked` + comment which criterion fired and
what a human should decide. Record `blocked (policy)` — this is cheap
triage, it does not consume quota. **When in doubt, block.**

## Step 3 — Implement (consumes a quota slot from here on)

1. Branch from the fetched base:
   `git switch -c agent/issue-<N> origin/main`. If the branch already
   exists locally or remotely (stale leftover, closed-unmerged PR), use
   `agent/issue-<N>-<YYYYMMDD>` instead — never reuse or delete the old
   one (it may encode a human's rejection; the PR body should mention
   the leftover so the human can clean up).
2. Implement the **minimum** change satisfying the acceptance criteria,
   honoring `### Out of scope` and all CLAUDE.md conventions (TDD for
   Engine/LLM layers, `nonisolated`, `String(localized:)`, no `!`, ...).
3. Tests: when Swift is touched, run the targeted suite during
   development and the full suite before review —
   `scripts/xcodebuild.sh test --tail 80` (pipefail-safe; never
   external `| tail`). Add tests covering each testable acceptance
   criterion. Docs-only changes skip xcodebuild.
4. Commit with Conventional Commits + emoji, referencing the issue in
   the body (`See #N` — not `Closes`, that belongs to the PR).

## Step 4 — Mandatory review (the Gungi substitute)

Launch the code-reviewer agent — this replaces the per-edit Opus review
hook used elsewhere and is the **only** review before a human sees the PR:

```
Agent(subagent_type: "code-reviewer", model: "opus",
      prompt: "Review all changes on this branch: git diff origin/main...HEAD ...")
```

- **PASS** → Step 5.
- **FAIL** → fix the confirmed findings, re-run the reviewer once. A
  second FAIL = failed attempt (hard rule 4: retry or block).
- **SCOPE_TOO_LARGE / truncated** → hard rule 6: block, no PR. Do not
  shrink the review's scope to force a pass.

## Step 5 — Draft PR + label release (completes the issue)

```bash
git push -u origin agent/issue-<N>
gh pr create --draft --base main --label <type-label> \
  --title "<emoji> <type>: <summary>" --body ...
```

PR body must contain:

- `Closes #<N>` (the human's merge closes the issue — the skill never does)
- A correspondence table: each acceptance criterion → how the diff
  satisfies it → the test that covers it (or why untestable)
- **Judgment calls**: anything you were unsure about, interpreted, or
  deliberately left out — the morning reviewer reads this first
- Test results (suite + outcome)

Then release the queue slot so the next night does not re-pick the issue:

```bash
gh issue edit <N> --remove-label agent-ready
gh issue comment <N> --body "Draft PR: <url> — awaiting human review."
```

Record `completed`.

## Step 6 — Retry / blocked bookkeeping

A failed attempt (criteria cannot be met, tests cannot pass, review
FAILs twice) → start over once from Step 3 with a fresh branch
(`agent/issue-<N>-<YYYYMMDD>` if needed). Second failure:

```bash
gh issue edit <N> --remove-label agent-ready --add-label agent-blocked
gh issue comment <N> --body "..."   # what was attempted, what failed, logs/errors
```

Record `blocked (implementation)`. Both attempts together consume ONE
quota slot.

## Step 7 — Digest + report

Compose the run summary JSON (schema in `append_digest.py`'s docstring:
`run_id`, `notes`, per-issue `number`, `title`, `outcome`
(`completed` / `skipped-pr-open` / `skipped-needs-detail` /
`blocked-policy` / `blocked-implementation`), `branch`, `pr_url`,
`note`) to a temp file, then:

```bash
python3 .claude/skills/queue-consumer/scripts/append_digest.py \
  --results /tmp/queue_results_<DATESTAMP>.json
```

Without `--digest`, the script resolves the **main checkout** via
`git rev-parse --git-common-dir` (the `.git`-basename check is the
wrong-target catch) and writes `data/queue/digest.md` there — a present
file must carry the section marker, an absent one is bootstrapped from a
scaffold. The digest is a gitignored **local log**: the section is
appended in place and is NOT committed (nothing to commit — it no longer
shows in `git status`). Mirrors `data/factory/digest.md`.

Finally, report to the user (or the routine transcript): per-issue
outcomes with PR URLs, blocked/skipped reasons, and the digest location.
