# GHA gating for a long-lived branch

Reference for CI on a long-lived integration / release-train / spike-staging branch. No such branch exists today — every workflow triggers on `main` plus `schedule` / `workflow_dispatch` — so this is a playbook, not a description of the tree.

The gate is **two layers**, each at **two directions**.

**Layer A — trigger filter** (`on.pull_request.branches`)
Controls whether the workflow fires at all. The default project shape `branches: [main]` means PRs targeting any other branch fire ZERO jobs — including a job carefully gated below.

**Layer B — job-level `if:`**
Within a fired workflow, three event shapes to cover for a long-lived branch `feature/X`:

1. `push` to `feature/X` → `github.ref == 'refs/heads/feature/X'`
2. `pull_request` INTO `feature/X` (e.g. weekly feature PRs) → `github.base_ref == 'feature/X'`
3. `pull_request` FROM `feature/X` (e.g. the final merge to main) → `github.head_ref == 'feature/X'`

For `pull_request` events, `github.ref` is `refs/pull/<N>/merge`, NOT the source or target branch. A single-ref guard `github.ref == 'refs/heads/...'` misfires on every PR.

## Procedure

1. **Check the trigger filter first.** A job-level `if:` only matters if the workflow actually fires; `on.pull_request.branches` is the gate above the gate.
2. **For inverse-gated jobs** (e.g. `ui-test` SKIPPED on the spike branch), the same enumeration applies — every case the affirmative job covers, the inverse must un-cover.
3. **Verify by opening a dummy PR.** The first exercise of an `if:` gate should be a draft PR, not the GO merge, so a misconfiguration is cheap to spot.

Workflow trigger layering produces zero-cost gaps: a broken `if:` on a job that never fires looks identical to "correctly skipped". Both layers must be reasoned about explicitly.
