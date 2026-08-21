---
paths:
  - ".github/workflows/**"
  - "scripts/**"
---

# CI Workflows (GHA, macOS runners)

Traps when editing CI workflow YAML or supporting scripts.

## CI wall-clock budget per PR

Target **≤10 min**, ~12 min acceptable, **20 min is a blocker** — the feedback loop on UI-test-affected PRs is unusable there. UI tests run several times slower on CI simulators than locally, so estimate a new step's impact before proposing it.

## Shell scripting gotchas (macOS GHA runners and repo scripts)

### Rule 1 — bash 3.2 on macOS runners: no `mapfile` / `readarray`

`macos-*` runners default `/bin/bash` to 3.2. **Incompatible**: `mapfile` / `readarray`, `declare -A`, `${var^^}`, `<<<`. `ubuntu-*` has bash 5+, so a construct can pass one job and die in another.

### Rule 2 — a `run:` step has NO pipefail, so `cmd | tee file` masks failure

A `run:` step with no `shell:` key executes as **`bash -e {0}`** — `-e` only; `-eo pipefail` is what `shell: bash` *selects*. So `xcodebuild … 2>&1 | tee /tmp/log` reports a `** BUILD FAILED **` step green, on `tee`'s exit 0.

```bash
# (a) Die on failure — the common case.
set -o pipefail
xcodebuild … 2>&1 | tee /tmp/log

# (b) Survive the failure (e.g. parse the log for a PR comment), then decide.
#     Correct ONLY without pipefail.
xcodebuild … 2>&1 | tee /tmp/log || true
TEST_EXIT=${PIPESTATUS[0]}
```

**(a) and (b) don't compose.** Adding pipefail (or `shell: bash`) to a (b)-shaped step makes the pipeline exit non-zero, so `|| true` fires and resets `PIPESTATUS` to that of `true` — `PIPESTATUS[0]` reads 0 and **every failing run reports green**. Check which shape a step is before touching its exit handling, and never add pipefail without also removing the `|| true`.

### Rule 3 — an early-exiting reader under `pipefail` reports a MATCH as a failure

`grep -q` exits at its first match; the still-writing producer takes SIGPIPE and returns 141, which `pipefail` promotes to the pipeline's status — so `if ! producer | grep -q PAT` skips **because** the pattern matched. Fix the shape (capture, then test the captured text), never the option. `scripts/tests/staged-trigger-pipefail-test.sh` scans tracked shell scripts for that shape and prints the fix; three things sit deliberately outside its scope:

- **Other early-exiting readers** — `head`, `sed …q`, `awk …exit`, `grep -m N`. `grep -q` fails **open** (a gate skips); `| head` fails **loud** (a bare 141, no message — `scripts/analyze-streaming-diag.sh`).
- **Workflow YAML.** A bare `run:` has no pipefail (Rule 2), so `ci.yml`'s `printf … | grep -q` steps are latent — **adding `shell: bash` arms one**.
- **`core.quotepath=false` on the producer.** git octal-escapes *and* double-quotes a non-ASCII path by default, and the quotes defeat a `^`/`$`-anchored trigger pattern.

### Rule 4 — `$(set +o)` cannot round-trip errexit

`_old=$(set +o)` … `eval "$_old"` **drops a caller's `set -e`**: bash has already cleared errexit inside the command substitution, so the snapshot records `set +o errexit` regardless. errexit is the only option this hits — `nounset` and `pipefail` round-trip. Capture it separately (`case $- in *e*) had=1 ;; esac`) and re-apply on every restore path. Worked example: `scripts/sim-dest.sh`.

**A failing `source` aborts an errexit-on caller only in the bare form** — bash suppresses errexit for the left operand of `||`, so a `source … || { …; exit 1; }` call site depends on that `exit` being there.

## Required-check-safe path gating

`main` requires its status checks via a ruleset, and the two skip mechanisms diverge. A **job-level `if:` skip** reports "Success" and satisfies the check. A **workflow/trigger-level skip** (`on.<event>.paths` / `paths-ignore`, or the workflow not firing) leaves the check **"Pending"** and the ruleset blocks the merge forever — never path-filter at the `on:` trigger of a workflow that owns a required check. Gate at the **job** level: a cheap classifier job emits an output, each expensive job carries `needs:` plus an `if:` that runs unless the classifier cleared it (derivation in `ci.yml`'s `changes` job comments). Invariants:

1. **Conservative by inversion.** Any ambiguity — empty, unresolvable or API-errored file list — runs the full suite: `if: ${{ !cancelled() && needs.<classifier>.outputs.<flag> != 'false' }}`, never `== 'true'`. Reuse `scripts/precommit-gate-classify.sh` so CI and the pre-commit hook classify identically.
2. **Gate PRs only.** The non-PR set is `push` **plus** the daily `schedule` and `workflow_dispatch` canary — four event shapes; enumerate all four when adding a job `if:`, since a push/PR-only guard mis-handles the daily.
3. **Don't gate the cheap ubuntu drift guards** — same required-check risk, no benefit. Gate only the macOS jobs.
4. **`pr-comment` runs even when its deps skip — deliberately.** Its `if: !cancelled() && …` is a status function, so it does not inherit a skipped dependency; "fixing" it to a plain boolean makes the comment vanish. A plain boolean is the lever when you *do* want a consumer to skip with its dependency.
5. **Verify BOTH branches on dummy PRs**: a docs/web-only PR must skip the macOS jobs *and* still show required checks green; a trivial `.swift` PR must run them. The first exercise of an `if:` gate should be a draft PR, not the GO merge. A gating PR touching only `.github/` / `.claude/` skips those jobs on itself, so its *run* path is never exercised pre-merge. Long-lived-branch shapes: `docs/ci/gha-branch-gating.md`.
6. **A new guard job is advisory until the `main` ruleset lists it as required**, and the ruleset is untracked, so nothing in-repo prompts you. Register it **after** the guard's PR merges — doing it while another PR is open strands that PR on a check its branch cannot produce.

## Step-level `if:` — the implicit `success()` can be load-bearing

A **step** `if:` with no status-check function carries an implicit `success()`; adding `always()` / `failure()` / `!cancelled()` removes it, letting the step run after an earlier failure. Live case: `kmp-nightly.yml`'s "Measure warm-cache assembly (Stage-5 sizing)" step, whose implicit `success()` is all that stops its `clean` wiping the reports the `if: failure()` upload below collects.

A `continue-on-error: true` step's failure sets `outcome`=failure but `conclusion`=success, and status functions read `conclusion`, so a later `failure()` stays false. It does not cover a **job** timeout — hence that step's own `timeout-minutes`.

## Script unit tests (`scripts/tests/`) run in CI only — not the pre-commit hook

`scripts/tests/*-test.sh` unit-test the **scripts themselves** and run only in the CI "Shell gate tests" job; the pre-commit hook runs the *gate* scripts, which never exercise a curation script's own field-extraction logic. So a `scripts/` change can pass every local gate and still fail CI — watch for fixtures lagging a newly required field. Run the suite before pushing:

```bash
for t in scripts/tests/*-test.sh; do bash "$t" || echo "FAIL: $t"; done
```

### Synthetic git fixtures: anchor every directory an ignored entry sits under

git collapses a wholly-ignored **untracked** directory to its topmost untracked parent — `status --ignored` reports `!! Pastura/`, not `!! Pastura/DerivedData/`, unless something under `Pastura/` is tracked. A fixture repo tracks almost nothing, so it produces path shapes this repo cannot and every negative control passes for the wrong reason. Track a file under every directory an ignored entry will sit in, and assert per case that the exact entry string reached the code under test. Worked example: `prune-stale-worktrees-test.sh` § `assert_ignored_entry`.

### Skill-local harnesses are NOT auto-wired — each needs a `scripts/tests/` shim

`scripts/tests/skill-harness-wiring-test.sh` enforces the shim and names the missing path. What it cannot check: keep the harness ubuntu-runnable (python3 + jq + git; no Swift, no network), since the Shell-gate runner has no Xcode.

## Rename / namespace-sweep completion gate — `git grep`, both forms

Run a "0 remaining" sweep gate with `git grep -nF` over tracked files — never a plain `rg` over the worktree, which descends into `DerivedData` — in **both** the bare and the backslash-escaped form, repo-wide, never hand-picking directories. A `sed` expression inside a shell script stores `com\.tyabu12` on disk (backslash + dot, two chars), which the regex `com\.tyabu12` does **not** match, so the gate returns 0 while live occurrences remain.

```bash
git grep -nF 'com.tyabu12.Pastura'   # bare
git grep -nF 'com\.tyabu12'          # backslash-escaped on-disk literal
```

## `grep` is line-bound — call-shape CI guards miss multi-line calls

A guard matching a Swift call *shape* (`grep -E 'foo\([^)]*\bbar\b'`) silently passes once SwiftFormatter splits the call across lines — the tokens land on different lines and a regression sails through. Match the bare token anywhere, then post-filter comment lines (`grep -vE ':[[:space:]]*//'`) with a per-file `--exclude=` allow-list. **Self-test in the multi-line shape** SwiftFormatter would produce and confirm the script exits 1; a single-line self-test passes a guard that misses the real wrapped form. Reference: `scripts/check_engine_language_axis.sh`. The same blindness hits prose sweeps — grep the shortest stable token, not a phrase.

## Gate scripts: `::error file=` is repo-relative, and scope must be tracked-only

Two traps hitting a gate script's *reporting* and *scope*, not its logic — so tests of the verdict pass while both are broken.

**Annotation paths.** GitHub resolves `file=` relative to the repository root, so a script building paths from `REPO_ROOT="$(cd … && pwd)"` emits absolute ones that match no tracked file: the annotation loses all line linkage in the Files-changed view *while still rendering normally in the log*. Strip the prefix at emission and pass `line=` when a `grep -n` already has the number. Reference: `check-b-prime-isolation.sh` (`annotate_path`).

**Scope.** A gate asserting a **repository** invariant must read tracked files, never walk the worktree: `Pastura/DerivedData/` and `.build/artifacts/` both hold a vendored `llama.xcframework` after any local build, so a `find`-based check is **green on a fresh CI checkout and red on every developer machine** — the split CI structurally cannot show.

## One repo, many sub-actions — Dependabot splits them, the runtime does not

A multi-action repo referenced by sub-path (`github/codeql-action/init` and `.../analyze`) is one runtime but several Dependabot dependencies — a PR per sub-action, so the halves can merge at different versions and the action refuses to run. `scripts/check-action-pin-consistency.py` catches the resulting drift, but only after it happens. Referencing a *new* multi-action repo means adding a `groups:` entry for it in `.github/dependabot.yml`.

## Related

`.claude/rules/xcodebuild-cli.md` covers the agent-session analogue, with the opposite default: `scripts/xcodebuild.sh` sets its own `pipefail`, a GHA `run:` step has none (Rule 2).
