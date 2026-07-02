---
paths:
  - ".github/workflows/**"
  - "scripts/**"
---

# CI Workflows (GHA, macOS runners)

Four concern families when editing CI workflow YAML or supporting scripts on this repo: shell-language gotchas on the macOS runner, long-lived integration-branch gating shape, required-check-safe path gating, and the script unit-test suite that runs in CI only.

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

## Required-check-safe path gating

To skip an expensive job on irrelevant changes (e.g. the heavy macOS jobs on a web/docs-only PR), the **skip mechanism** decides whether the PR can still merge. `main` requires its status checks via a **ruleset**, and the two skip mechanisms diverge:

- **Job-level `if:` skip → reports "Success" → satisfies a required check.** Safe.
- **Workflow/trigger-level skip** (`on.<event>.paths` / `paths-ignore`, or the whole workflow not firing) → the check stays **"Pending"** → a required-check ruleset blocks the merge forever. This is the footgun; do NOT path-filter at the `on:` trigger for any workflow that owns a required check.

So gate at the **job** level: a cheap detection job classifies the diff and emits an output; each expensive job carries `needs: <classifier>` + an `if:` that runs unless the classifier explicitly cleared it (exact conservative form in invariant 1 below). When skipped, the required check is still satisfied. (Confirmed by GitHub docs "Troubleshooting required status checks"; impl in `.github/workflows/ci.yml` `changes` job, #642.)

Load-bearing invariants when adding/changing such gating:

1. **Conservative by inversion.** Default to running the full suite on any ambiguity — empty / unresolvable / API-errored file list ⇒ run. A *false skip* (a broken build merged because the gate wrongly skipped) is the worst case. Reuse `scripts/precommit-gate-classify.sh` so CI and the pre-commit hook classify identically (#625); note it emits `""` (not a token) on empty input, so the fail-safe lives in the job's bash, not the script. Extend the same posture to the *gated* jobs: write the gate as `if: ${{ !cancelled() && needs.<classifier>.outputs.<flag> != 'false' }}` (run UNLESS explicitly classified out), not `== 'true'`. `!cancelled()` drops the implicit needs-success gate, so a *failed* classifier job (empty output) runs the suite instead of failed-dependency-skipping the required check — a `== 'true'` gate would false-skip there.
2. **Gate PRs only; `main`/push runs unconditionally.** The classifier short-circuits every non-`pull_request` event to `ios=true`, so a merge to `main` always runs the full suite — stability on the integration branch outweighs the marginal saving, and it sidesteps any push-event diffing edge cases. The optimization spares redundant *PR* runs, not `main`.
3. **Don't gate the cheap ubuntu drift guards.** They cost little and gating them risks the same required-check trap for no benefit — gate only the macOS jobs.
4. **`pr-comment` runs even when its deps skip — deliberately.** It carries `if: !cancelled() && …`, a status function, so it does **not** inherit a skipped dependency: on a web/docs-only PR (macOS jobs skipped) it still runs and posts a "did not run / skipped" comment (cosmetically noisy, functionally fine). Don't "fix" it to a plain boolean or the comment vanishes. (Contrast: a *plain-boolean* `if:` WOULD inherit the skip — that's the lever when you want a consumer to skip alongside its dependency.)
5. **Verify BOTH branches on dummy PRs** (the "Long-lived branch gating — two layers × two directions" § `### Procedure` step 3 applies here too): one docs/web-only PR must skip the macOS jobs *and* still show the required checks green/mergeable; one trivial `.swift` PR must run them. A gating PR that touches only `.github/`/`.claude/` skips the macOS jobs on itself, so its *run* path is never exercised pre-merge — test it separately.

## `ci.yml` fires on four event shapes — enumerate all when editing an `if:`

`ci.yml` triggers are `push`(main) / `pull_request`(main) / `schedule`(daily
`cron: '11 1 * * *'` = 10:11 JST green-main canary) / `workflow_dispatch`. Both
`schedule` and `workflow_dispatch` are non-`pull_request`, so the `changes`
classifier short-circuits them to `ios=true` (invariant 2) — the daily is a
**full** CI run (all macOS jobs + drift guards), not ui-test-only. The
event-gated tail jobs stay correct because they name their event explicitly:
`coverage` (`event == 'push'`) and `pr-comment` (`event == 'pull_request'`) both
skip on schedule/dispatch. When adding a new job or `if:`, enumerate all four
shapes — a guard written only for push/PR silently mis-handles the daily run.

`ci-retry.yml` auto-retries the `schedule` arm with the **same** attempt budget
as `main push` (< 3), so a ui-test flake on the daily does not surface as a
false red; `workflow_dispatch` is intentionally **not** retried (human-initiated
and watched).

## Script unit tests (`scripts/tests/`) run in CI only — not the pre-commit hook

`scripts/tests/*-test.sh` unit-test the **scripts themselves** (e.g.
`gallery-scripts-test.sh` exercises `add-gallery-entry.sh` /
`promote-factory-to-gallery.sh` against fixtures). They run **only** in the CI
**"Shell gate tests"** job. The git pre-commit hook runs the *gate* scripts
(`gallery-precommit-gate.sh` → `check-gallery-entry.sh`, blocklist, nav-map,
scenario-editor-funnel), which validate inputs/outputs (SHA, schema, drift) but
**never exercise a curation script's own field-extraction logic**. So a
`scripts/` change can pass the local commit and every pre-commit gate yet still
fail CI.

**Apply:** when editing any `scripts/*.sh`, run the suite locally before pushing:

```bash
for t in scripts/tests/*-test.sh; do bash "$t" || echo "FAIL: $t"; done
```

Watch especially for test fixtures that lag a new required field: #788 (the
art-tile PR that also added `phases:` extraction to `add-gallery-entry.sh`) made
that extraction required, aborting every `gallery-scripts-test.sh` case whose
fixture builder (`mk_factory` / `mk_gallery_yaml`) predated it. `check-gallery-entry.sh`
never runs the extraction, so it was green locally, red in CI.

### Skill-local harnesses are NOT auto-wired — each needs a `scripts/tests/` shim

The Shell-gate glob is `scripts/tests/*-test.sh` **only**, so a skill's own
self-test at `.claude/skills/<skill>/tests/run_tests.sh` runs **nowhere** in CI
by default — silent zero coverage (the #888 / #891 gap). Wire each one with a
thin shim `scripts/tests/<skill>-test.sh` that delegates:

```bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$REPO_ROOT/.claude/skills/<skill>/tests/run_tests.sh"
```

`scripts/tests/skill-harness-wiring-test.sh` enforces this — it fails the
Shell-gate job when any harness lacks a shim, and the shim's delegation must be
a **live** `bash …/run_tests.sh` line (a path named only in a header comment
does not count). Keep the harness ubuntu-runnable (python3 + jq + git, no Swift,
no network) since the Shell-gate runner has no Xcode.

## Rename / namespace-sweep completion gate — `git grep`, both forms

For a rename or namespace-sweep "0 remaining" completion gate, use
`git grep -nF '<literal>'` over tracked files — **not** a plain `rg` over the
worktree — and run it for **both** the bare and the backslash-escaped form.

Two failure modes a plain `rg '<pattern>'` gate hit on a bundle-id rebrand sweep:

1. **Escaped-form blind spot.** A shell script (`scripts/analyze-streaming-diag.sh`)
   contained `sed 's/.*\[com\.tyabu12\.Pastura...\]//'` — on disk that's
   `com\.tyabu12` (backslash + dot = two chars), so the regex `com\.tyabu12`
   (`com` + dot + `tyabu12`) did **not** match. The gate returned 0 while live
   occurrences remained; caught only by code review. For regex-y patterns use a
   backslash-tolerant form (`com[\\]?\.tyabu12`), or `-F` both literals.
2. **`rg` traverses the worktree and can hang** (~tens of minutes) on a huge
   `DerivedData/*.xcresult` or a symlink loop even with `--glob '!**/DerivedData/**'`.

**Apply** — at sweep gates, run both forms tracked-only and repo-wide (no
hand-picking dirs — a hand-picked `docs/ + scripts/` once missed
`.claude/rules/xcodebuild-cli.md`):

```bash
git grep -nF 'com.tyabu12.Pastura'   # bare
git grep -nF 'com\.tyabu12'          # backslash-escaped on-disk literal
```

`git grep` is tracked-only (fast, never descends into ignored/huge files) and
repo-wide by default. Pairs with the "grep ALL instances before scoping"
discipline.

## Related

`.claude/rules/xcodebuild-cli.md` covers the agent-session analogue (`xcodebuild | tail` exit-code masking when invoked from Claude Code). The CI form here is `|| true` defeating `pipefail`; same root family.
