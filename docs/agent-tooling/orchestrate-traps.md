# `/orchestrate` — traps behind the short wording

On-demand companion to [`.claude/skills/orchestrate/SKILL.md`](../../.claude/skills/orchestrate/SKILL.md).
The skill states each rule once; this file keeps the mechanism, so the rule can be re-derived when it
looks removable. Nothing here is loaded per invocation.

## Worktree and cwd

- **Non-isolation subagents do not reliably inherit the worktree cwd.** A reviewer whose bare `git`
  resolved to the main checkout returned an empty diff, which reads as a false FAIL. Hence
  `git -C {WORKTREE_ROOT}` in every subagent prompt, captured once — never a `$(…)` the subagent
  re-runs.
- **The same failure reads as success for the implementer.** `scripts/xcodebuild.sh` resolves its
  repo root from cwd, so a run that landed in the main checkout builds and tests *that* tree and
  prints `** TEST SUCCEEDED **` for unrelated code. The path-rooting sentence in the prompt is a soft
  instruction, so the prompt also asks for `pwd`; the main-session full-suite run at the end of
  Step 3 is the backstop.
- **`-C` is git-only.** The wrapper has no `-C`, and the allowlist entry for it is an exact-prefix
  literal: a `cd … &&` prefix, an absolute path, or a leading env-var assignment raises an approval
  prompt that stalls an unattended subagent. The git allowlist entries are equally bare, yet
  `git -C <path> diff` has run unprompted — the two are not the same case, and only the xcodebuild
  one is measured, so do not generalize either way.
- **Absolute Edit/Write paths carried over from a pre-worktree tool result point at the main
  checkout.** Invalidate them after `EnterWorktree`.
- **Post-merge `ExitWorktree(action: "remove")` refuses on a squash merge** — the merged commit has
  a new SHA, so local commits read as unmerged by ancestry. `discard_changes: true` after the user
  confirms the merge landed.

## Commits

- **The pre-commit SwiftLint step lints the whole worktree, not the staged set.** An unstaged edit
  to a *later* item's file (one that trips a length cap, say) fails the *current* item's commit.
  `git stash push -- <later-item-files>` before the focused commit, then pop.
- **A delegated item can satisfy every acceptance condition and still leave an instance of the
  shape it was removing** — the prompt bounds what was *asked*, not what the item *mandates*. Grep
  the whole file for the OLD shape before committing (#1453 item 2 is the worked example).

## Delegation

- **`claude-kit:implementer` declares no `tools:` key** (it inherits `EnterWorktree` /
  `ExitWorktree`, so the exclusion can only be a prompt instruction) **and pins `effort: medium`**
  (`Agent` has no `effort` parameter). A `🎭` item therefore runs at Opus/medium; if fix rounds rise,
  escalate to a general Opus subagent at session effort rather than re-dispatching the implementer.
- **The four `OUTCOME` values carry opposite stash instructions** — `design-decision` wants the
  partial work kept, `failed` wants it stashed, `scope-refusal` has none — so the outcome is a
  literal line, never inferred from prose.
- **A silent in-session fallback when the plugin agent is missing** degrades every `🎭` item back to
  pre-split behaviour with no signal that routing stopped working. Stop and surface it.

## Review and verification

- **CI is not a backstop for the build-irrelevant carve-out.** `.github/workflows/ci.yml` reuses
  `scripts/precommit-gate-classify.sh` for PR path-gating, so a build-irrelevant PR skips
  `lint-and-test` and `ui-test` on CI too. What covers the post-merge state is that a push to `main`
  runs the full iOS suite regardless of paths — in the workflow, not the script.
- **A rebase or non-conflicting auto-merge can drop upstream entries from `Localizable.xcstrings`**
  without surfacing a conflict, which is why the Step 4 rebase check is mandatory for generated /
  data files.
- **Round ≥ 2 on self-authored prose has negative expected value.** In #1516, every round-2
  Critical and Warning attacked round-1's fix prose; each round mints new attackable claims at
  ~100k tokens. Step 4 is one round by design (#1519) — residuals go to the PR body, not a loop.

## Degraded mode (no `gh`)

- `gh auth status` runs first, before the `#N` fetch and Resumption Detection, because both depend
  on its verdict.
- `git symbolic-ref refs/remotes/origin/HEAD` returns `refs/remotes/origin/main` and `--short`
  alone returns `origin/main`; both break the `git fetch` / `rev-list` / `pull` / `switch`
  consumers of `DEFAULT_BRANCH`. Only `--short … | sed 's|^origin/||'` yields a bare branch name
  (upstream: claude-kit#34).
