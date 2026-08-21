# `/orchestrate` — the mechanisms behind its rules

On-demand companion to [`.claude/skills/orchestrate/SKILL.md`](../../.claude/skills/orchestrate/SKILL.md).
The skill states each rule; this file keeps only *why*, so a rule can be re-derived when it looks
removable. Nothing here is loaded per invocation.

## Worktree and cwd

- **`git -C {WORKTREE_ROOT}` in every subagent prompt:** a non-isolation subagent's cwd has resolved
  to the main checkout in practice. For a reviewer that yields an empty diff — a false FAIL. For an
  implementer it is worse: `scripts/xcodebuild.sh` resolves its repo root from cwd, so the run tests
  the *wrong* tree and prints `** TEST SUCCEEDED **` — a false green. Hence the `pwd` request; the
  main-session full-suite run at the end of Step 3 is the backstop.
- **`scripts/xcodebuild.sh` stays bare while git takes `-C`:** the wrapper has no `-C`, and its
  allowlist entry is an exact-prefix literal, so a `cd` prefix raises an approval prompt that stalls
  an unattended subagent. The git entries are equally bare yet `git -C <path> diff` has run
  unprompted — only the xcodebuild case is measured, so do not generalize either way.
- **Absolute Edit/Write paths from a pre-worktree tool result** point at the main checkout.
- **Post-merge `ExitWorktree(action: "remove")` refuses** because a squash merge gives the merged
  commit a new SHA, so local commits read as unmerged by ancestry.

## Commits

- **The pre-commit SwiftLint step lints the whole worktree, not the staged set.** An unstaged edit
  to a *later* item's file (one that trips a length cap, say) fails the *current* item's commit.
  `git stash push -- <later-item-files>` before the focused commit, then pop.
- **"Grep for the OLD shape before committing":** a delegated item has satisfied every acceptance
  condition and still left an instance of the shape it was removing — the prompt bounds what was
  *asked*, not what the item *mandates* (#1453 item 2).

## Delegation

- **Why the `🎭` prompt restates tool exclusions and asks for an `OUTCOME` line:**
  `claude-kit:implementer` declares no `tools:` key (so it inherits `EnterWorktree` / `ExitWorktree`)
  and pins `effort: medium` (`Agent` has no `effort` parameter). The four outcomes carry opposite
  stash instructions — `design-decision` keeps the partial work, `failed` stashes it,
  `scope-refusal` has none — so the outcome must be a literal line, not inferred from prose.
- **Why a missing plugin agent stops the run instead of falling back in-session:** a silent
  fallback degrades every `🎭` item to pre-split behaviour with no signal that routing stopped
  working.

## Review and verification

- **Why CI is not a backstop for the build-irrelevant carve-out:** `.github/workflows/ci.yml` reuses
  `scripts/precommit-gate-classify.sh` for PR path-gating, so a build-irrelevant PR skips
  `lint-and-test` and `ui-test` on CI too. A push to `main` runs the full iOS suite regardless of
  paths — in the workflow, not the script.
- **Why the Step 4 rebase check is mandatory for generated / data files:** a rebase or
  non-conflicting auto-merge has dropped upstream `Localizable.xcstrings` entries without a conflict.
- **Why Step 4 is one round:** in #1516 every round-2 Critical and Warning attacked round-1's fix
  prose; each round mints new attackable claims at ~100k tokens (#1519). Residuals go to the PR
  body, not a loop.

## Degraded mode (no `gh`)

- **Why `gh auth status` runs first:** the `#N` fetch and Resumption Detection both depend on its
  verdict.
- **Why the `DEFAULT_BRANCH` fallback is `--short … | sed 's|^origin/||'`:** `git symbolic-ref
  refs/remotes/origin/HEAD` returns `refs/remotes/origin/main` and `--short` alone returns
  `origin/main`; both break the `git fetch` / `rev-list` / `pull` / `switch` consumers (upstream:
  claude-kit#34).
