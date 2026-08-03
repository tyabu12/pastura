---
paths:
  - ".github/workflows/**"
  - "scripts/**"
---

# CI Workflows (GHA, macOS runners)

Nine concern families when editing CI workflow YAML or supporting scripts on this repo: the CI wall-clock budget per PR, shell-language gotchas on the macOS runner, long-lived integration-branch gating shape, required-check-safe path gating, step-level `if:` semantics, the script unit-test suite that runs in CI only, rename/namespace-sweep completion gates, grep's line-boundedness in call-shape guards, and gate scripts' annotation paths and tracked-only scope.

## CI wall-clock budget per PR

Target **≤10 min**, up to ~12 min acceptable, **20 min is a blocker** — at 20 min the feedback loop on UI-test-affected PRs is unusable. When adding CI steps (new test targets, matrix builds, coverage passes), estimate wall-clock impact **before** proposing; if a change pushes above ~12 min, surface the trade-off explicitly (drop a redundant test, build-sharing, move to a nightly schedule) rather than shipping a slow suite and fixing later. UI tests especially run several times slower on CI simulators than locally — budget them aggressively.

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

### Rule 2 — a `run:` step has NO pipefail, so `cmd | tee file` masks failure

A `run:` step without an explicit `shell:` key executes as **`bash -e {0}`** — `-e` only. The `-eo pipefail` form is what `shell: bash` *selects*; it is not the default. Per [GitHub's workflow-syntax reference](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsshell), verbatim: default → `bash -e {0}`; `shell: bash` → `bash --noprofile --norc -eo pipefail {0}`.

So this **silently passes** a failed build — the pipeline's exit code is `tee`'s 0:

```bash
xcodebuild … 2>&1 | tee /tmp/log     # ✗ `** BUILD FAILED **` reports the step GREEN
```

Pick one, by whether the step must survive the failure:

```bash
# (a) Die on failure — the common case. `set -o pipefail` above the pipe.
set -o pipefail
xcodebuild … 2>&1 | tee /tmp/log

# (b) Continue past failure (e.g. to parse the log for a PR comment), then
#     decide explicitly. Correct ONLY without pipefail — see the trap below.
xcodebuild … 2>&1 | tee /tmp/log || true
TEST_EXIT=${PIPESTATUS[0]}
```

**The trap: (a) and (b) don't compose.** Adding `set -o pipefail` (or `shell: bash`) to a step shaped like (b) **breaks it silently**. Without pipefail the pipeline exits 0 (tee's status), so `|| true` never fires and `PIPESTATUS[0]` holds xcodebuild's real status. Turn pipefail on and the pipeline exits non-zero, `|| true` fires, and `PIPESTATUS` is reset to that of `true` → `PIPESTATUS[0]` reads 0 and **every failing test run reports green**. Verified on bash 3.2 (the macOS-runner version):

```
$ bash -e -c 'false | tee /dev/null || true; echo ${PIPESTATUS[0]}'            # → 1  (correct)
$ bash -eo pipefail -c 'false | tee /dev/null || true; echo ${PIPESTATUS[0]}'  # → 0  (broken)
```

**Apply:** when adding a pipe to an existing step, check which shape it is before touching its exit handling — and never add pipefail to a `|| true` + PIPESTATUS step without also removing the `|| true`. Motivating incident: the Release-build step followed this rule's *earlier* advice ("just write `cmd | tee log`, GHA defaults to pipefail") and masked a `** BUILD FAILED **` as green; the failure surfaced one step later as a misleading "Expected exactly 1 Release binary, found 0" (#1141).

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
2. **Gate PRs only; `main`/push runs unconditionally.** The classifier short-circuits every non-`pull_request` event to `ios=true`, so a merge to `main` always runs the full suite — stability on the integration branch outweighs the marginal saving, and it sidesteps any push-event diffing edge cases. The optimization spares redundant *PR* runs, not `main`. That non-PR set is `push` **plus** the daily `schedule` + `workflow_dispatch` canary, so `ci.yml` fires on four event shapes — enumerate all four when adding a job `if:` (a push/PR-only guard silently mis-handles the daily); the schedule/dispatch/concurrency mechanics live in ci.yml's `on:`/`concurrency` comments.
3. **Don't gate the cheap ubuntu drift guards.** They cost little and gating them risks the same required-check trap for no benefit — gate only the macOS jobs.
4. **`pr-comment` runs even when its deps skip — deliberately.** It carries `if: !cancelled() && …`, a status function, so it does **not** inherit a skipped dependency: on a web/docs-only PR (macOS jobs skipped) it still runs and posts a "did not run / skipped" comment (cosmetically noisy, functionally fine). Don't "fix" it to a plain boolean or the comment vanishes. (Contrast: a *plain-boolean* `if:` WOULD inherit the skip — that's the lever when you want a consumer to skip alongside its dependency.)
5. **Verify BOTH branches on dummy PRs** (the "Long-lived branch gating — two layers × two directions" § `### Procedure` step 3 applies here too): one docs/web-only PR must skip the macOS jobs *and* still show the required checks green/mergeable; one trivial `.swift` PR must run them. A gating PR that touches only `.github/`/`.claude/` skips the macOS jobs on itself, so its *run* path is never exercised pre-merge — test it separately.

## Step-level `if:` — the implicit `success()` can be load-bearing

A **step** `if:` with no status-check function carries an implicit `success()`; adding `always()` / `failure()` / `!cancelled()` **removes** it, letting the step run after an earlier one failed. (Job-level contrast: § "Required-check-safe path gating" invariants 1 and 4 drop the implicit gate *deliberately*. Same mechanism, opposite valence — don't conflate the two scopes.)

**Apply** — before adding a status function to a step `if:`, check what the implicit gate was doing. Live case: `kmp-nightly.yml`'s **"Measure warm-cache assembly (Stage-5 sizing)"** step — its implicit `success()` is the only thing stopping its `clean` from wiping the reports that the `if: failure()` upload below it collects. Full rationale is inline above that step.

Related, on the same step: a `continue-on-error: true` step's failure sets `outcome`=failure but `conclusion`=success, and status functions read `conclusion` — so a later `failure()` stays false. `continue-on-error` does not cover a **job** timeout, which is why that step also carries its own `timeout-minutes`.

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

### Synthetic git fixtures: anchor every directory an ignored entry sits under

git collapses a wholly-ignored **untracked** directory up to its topmost untracked
parent — `status --ignored` reports `!! Pastura/`, not `!! Pastura/DerivedData/`,
unless something under `Pastura/` is tracked. A fixture repo tracks almost nothing,
so it silently produces path shapes this repo cannot.

**Apply**: track a file under every directory an ignored entry will sit in, and
assert per case that the exact entry string reached the code under test. Skip it
and the positive case still fails loudly while every negative control passes for
the wrong reason — the same false-green shape § "Gate scripts" flags for
`mktemp -d` fixtures, from a different cause. Worked example (recurred #1340,
#1352): `scripts/tests/prune-stale-worktrees-test.sh` § `assert_ignored_entry`.

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

## `grep` is line-bound — call-shape CI guards miss multi-line calls

A CI guard matching a Swift call *shape* (`grep -E 'foo\([^)]*\bbar\b'`) silently
passes when SwiftFormatter splits the call across lines — the two tokens land on
different lines, so the pattern never matches and a regression sails through.
`rg -U` multiline mode works but ripgrep is **not** pre-installed on
`ubuntu-latest` (adds an `apt-get install ripgrep` step). Portable fix: match the
bare token anywhere, then post-filter comment lines (`grep -vE ':[[:space:]]*//'`),
plus a per-file allow-list (`--exclude=`) for legitimate authoring sites.
**Self-test before commit**: inject a regression in the *multi-line* shape
SwiftFormatter would produce and confirm the script exits 1 — a single-line
self-test passes a guard that misses the real wrapped form. Reference:
`scripts/check_engine_language_axis.sh`. The same line-bound blindness hits prose
sweeps (a markdown link wrapped across two lines is invisible to a one-line
pattern) — grep the shortest stable token (a bare filename), not a phrase. Sibling
grep-completeness trap: § "Rename / namespace-sweep completion gate".

## Gate scripts: `::error file=` is repo-relative, and scope must be tracked-only

Two traps that hit a gate script's *reporting* and *scope* rather than its logic,
so tests of the verdict pass while both are broken.

**Annotation paths.** GitHub resolves an annotation's `file=` **relative to the
repository root**. A script that builds paths from a `REPO_ROOT="$(cd … && pwd)"`
emits absolute ones, which match no tracked file — the annotation degrades to a
job-level message with no line linkage in the Files-changed view, *while still
rendering as a normal annotation in the log*. That is why it ships unnoticed.
Strip the prefix at emission, and pass `line=` whenever a `grep -n` already has
the number. Reference: `tools/kmp-gate-spike/scripts/check-b-prime-isolation.sh`
(`annotate_path`).

**Scope.** A gate asserting a **repository** invariant must read tracked files
(`git ls-files` / `git grep`), never walk the worktree. Build output is the
counterexample that bites: `Pastura/DerivedData/` and `.build/artifacts/` both
hold a vendored `llama.xcframework` after any local build, so a `find`-based
check is **green on a fresh CI checkout and red on every developer machine** —
the split least likely to be noticed, since CI never shows it. (§ "Rename /
namespace-sweep completion gate" reaches the same tracked-only call from the
other direction: escaped-form blind spots and `rg` hanging on DerivedData.)

**Testing both.** Neither is observable from a passing run, so a perturbation
test must force each: an annotation assertion needs a fixture **inside** the repo
(under a gitignored path, e.g. `Pastura/DerivedData/`, removed immediately) —
one built in `mktemp -d` never takes the relativizing branch and the assertion
silently exempts every case it sees. See #1171 for both incidents.

## Related

`.claude/rules/xcodebuild-cli.md` covers the agent-session analogue (`xcodebuild | tail` exit-code masking when invoked from Claude Code). Same root family — a pipe hides the head's exit status — but note the two contexts differ in their default: `scripts/xcodebuild.sh` sets its own `pipefail`, whereas a GHA `run:` step has none (Rule 2).
