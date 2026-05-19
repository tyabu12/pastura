---
paths:
  - ".github/workflows/**"
  - "scripts/**"
---

# CI Workflows (GHA, macOS runners)

Two concern families when editing CI workflow YAML or supporting scripts on this repo: shell-language gotchas on the macOS runner, and long-lived integration-branch gating shape.

## Shell scripting gotchas (macOS GHA runners)

### Rule 1 — bash 3.2 on macOS runners: no `mapfile` / `readarray`

GHA `macos-*` runners default `/bin/bash` to 3.2 (Apple ships 3.2 to avoid GPLv3). bash 4+ builtins fail with `command not found`.

**Incompatible on bash 3.2**: `mapfile` / `readarray`, `declare -A` (associative arrays), `${var^^}` (case conversion), `<<<` (here-string).

**Portable array-from-find idiom**:

```bash
RESULTS=()
while IFS= read -r -d '' f; do
  RESULTS+=("$f")
done < <(find … -print0)
```

Alternative: `shell: /opt/homebrew/bin/bash` on the step (pre-installed on runner images). Document *why* — mixing homebrew bash and system bash across steps is a consistency landmine.

Linux runners (`ubuntu-*`) have bash 5+ — the gotcha is macOS-specific.

### Rule 2 — `cmd | tee file || true` + `PIPESTATUS[0]` is broken

```bash
xcodebuild … 2>&1 | tee /tmp/log || true
TEST_EXIT=${PIPESTATUS[0]}
exit ${TEST_EXIT:-0}
```

**Does not capture xcodebuild's exit.** `|| true` consumes the pipeline's failure **and** resets PIPESTATUS, so `PIPESTATUS[0]` reads 0 even when xcodebuild failed.

GHA's default shell runs with `set -eo pipefail`. Just write:

```bash
xcodebuild … 2>&1 | tee /tmp/log
```

xcodebuild's non-zero exit propagates through the pipe and fails the step. No `|| true`, no PIPESTATUS dance.

Only reach for `|| true` + `PIPESTATUS` when you genuinely need to capture pipe-head exit without failing the step — rare. Verify empirically that PIPESTATUS survives in your shell; don't assume.

When replicating an existing CI pattern into a new job, inspect it for this bug first.

## Long-lived branch gating — two layers × two directions

For CI on long-lived integration / release-train / spike-staging branches, the gate is **two layers**, each at **two directions**:

**Layer A — trigger filter** (`on.pull_request.branches`)
Controls whether the workflow fires at all. Default project shape `branches: [main]` means PRs targeting any other branch fire ZERO jobs — including a job carefully gated below.

**Layer B — job-level `if:`**
Within a fired workflow, three event shapes to cover for a long-lived branch `feature/X`:

1. `push` to `feature/X` → `github.ref == 'refs/heads/feature/X'`
2. `pull_request` INTO `feature/X` (e.g. weekly feature PRs) → `github.base_ref == 'feature/X'`
3. `pull_request` FROM `feature/X` (e.g. final merge to main) → `github.head_ref == 'feature/X'`

For `pull_request` events, `github.ref` is `refs/pull/<N>/merge`, NOT the source or target branch. Single-ref guard `github.ref == 'refs/heads/...'` misfires on every PR.

### The bias trap

Critic prompts asking "is this `if:` correct?" tend to anchor on whichever direction the human implementer was thinking about. Force enumeration of every event shape (push to branch / PR INTO branch / PR FROM branch / PR to main / push to main) before answering.

### Procedure

1. **Check trigger filter first.** Job-level `if:` only matters if the workflow actually fires. `on.pull_request.branches` is the gate above the gate.
2. **For inverse-gated jobs** (e.g. ui-test SKIPPED on the spike branch), the same enumeration applies — every case the affirmative job covers, the inverse must un-cover.
3. **Verify by opening a dummy PR.** First exercise of `if:` blocks should be a draft PR, not the GO merge, so misconfiguration is cheap to spot.

Workflow trigger layering produces zero-cost gaps — broken `if:` on a job that never fires looks identical to "correctly skipped". Both layers must be reasoned about explicitly.

## Related

`.claude/rules/xcodebuild-cli.md` covers the agent-session analogue (`xcodebuild | tail` exit-code masking when invoked from Claude Code). The CI form here is `|| true` defeating `pipefail`; same root family.
