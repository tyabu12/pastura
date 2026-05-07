# xcodebuild CLI Rules

Always-loaded — see CLAUDE.md "Context-Specific Rules" for the
loading-mode rationale.

Local `xcodebuild test` / `build` invocations — including the
`git commit` pre-commit hook — go through `scripts/xcodebuild.sh`.
CI bypasses the wrapper (uses `xcodebuild ... -parallel-testing-enabled NO`
inline; SPM cache key depends on the default `~/Library/...`
DerivedData path — see [#189](https://github.com/tyabu12/pastura/issues/189)).

## Canonical invocation

**Run from the repository root with the cwd-relative path:**

```bash
scripts/xcodebuild.sh <subcommand> [--tail N] [args]
```

Allowlist: `Bash(scripts/xcodebuild.sh*)` and `Bash(source scripts/sim-dest.sh)`.
Both are exact-prefix literal matches — do **not** introduce variable
expansion (`"$xcb" ...`), `cd ... && scripts/xcodebuild.sh ...`,
leading env-var assignments
(`PASTURA_SKIP_XCSTRINGS_SYNC=1 scripts/xcodebuild.sh ...`), or
absolute paths in agent invocations. They bypass the allowlist and
trigger an approval prompt.

`scripts/xcodebuild.sh` resolves `REPO_ROOT` internally so
subdirectory invocations still produce correct paths — but the
allowlist match is on the literal command prefix, so always run from
the repo root in agent sessions.

### Why cwd-relative (#31373)

Claude Code's permission safety heuristic raises an approval dialog
for any executed command containing `$(...)`, regardless of `allow`
rules ([anthropics/claude-code#31373](https://github.com/anthropics/claude-code/issues/31373) — OPEN).
The previous canonical form used `$(git rev-parse --show-toplevel)/scripts/...`;
the cwd-relative form sidesteps the heuristic.

Hook commands in `.claude/settings.json` continue to use the `$()`
form because hooks execute as direct shell processes and bypass the
permission gate (and the heuristic). The asymmetry between allowlist
entries and hook commands is intentional.

## When to use what

| Scope | Command |
|---|---|
| TDD red/green (single class) | `scripts/xcodebuild.sh test -only-testing PasturaTests/<Class>` |
| Pre-PR full local run | `scripts/xcodebuild.sh test` |
| Build only (no tests) | `scripts/xcodebuild.sh build` |
| Cap output for context-window budget | `scripts/xcodebuild.sh <cmd> --tail N [args]` |
| CI full run | `.github/workflows/ci.yml` (bypasses wrapper) |

Skip UI tests with `-skip-testing:PasturaUITests` when the change
does not touch UI (UI tests are not required for MVP). Ollama
integration tests require `OLLAMA_INTEGRATION` env var enabled in the
scheme; otherwise auto-skipped.

## --tail (built-in, pipefail-safe)

`--tail N` is a wrapper-only flag. xcodebuild uses single-dash flags
so `--`-prefixed names are unambiguous. Accepted at any position;
last value wins on duplicates. Use this instead of external `| tail`
— external tail defeats `pipefail`, masking failed builds as exit 0
(memory `feedback_xcodebuild_pipefail.md`).

External `| grep` is OK for filtering, but the pipe replaces the
wrapper's exit code with grep's. Verify success by grepping output
for `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` (or the
corresponding `FAILED` markers), or use caller-side `set -o pipefail`.
When the SUCCEEDED marker has been trimmed off entirely:
`xcrun xcresulttool get test-results summary --path "$XCRESULT" --format json`.

## Wrapper behavior

- **`test`**: UDID-pinned simulator + `-parallel-testing-enabled NO`
  (CI workaround for within-process clone cascade — [#189](https://github.com/tyabu12/pastura/issues/189)).
- **`build`**: `generic/platform=iOS Simulator`, no UDID booking,
  exports `PASTURA_SKIP_SIM_WAIT=1` to bypass the simulator gate.
- **Auto-sync**: runs `xcrun xcstringstool extract` + `sync` against
  `Pastura/Pastura/Resources/Localizable.xcstrings` before xcodebuild
  ([#293](https://github.com/tyabu12/pastura/issues/293)). Opt out
  with `PASTURA_SKIP_XCSTRINGS_SYNC=1` (already set in the pre-commit
  hook so commits do not mutate the catalog outside the staging
  index). Failures write a sentinel at
  `Pastura/DerivedData/.xcstrings-sync-failed` and return 0 — never
  blocks build.
- **DerivedData**: pinned to worktree-local `Pastura/DerivedData/`
  via `-derivedDataPath "$DERIVED_DATA"`. **Pass with a space, not
  `=`** — the `=` form is silently ignored (Xcode 15.4+).

## Concurrent-session simulator gate

`sim-dest.sh` blocks at `source` time if another `xcodebuild test`
with `,id=<UDID>` destination is already running on this machine
(poll 5s / jitter 1.0–5.0s / 15-min timeout). Build-only invocations
bypass the gate (`generic/platform=...`, no UDID).

Override (rare manual operation, e.g. parallel-suite work or
`xcrun simctl` / `xcodebuild -showBuildSettings` inspection):

```bash
PASTURA_SKIP_SIM_WAIT=1 source scripts/sim-dest.sh
```

This exact form does not match the allowlist entry and triggers an
approval prompt by design.

If the gate consistently times out and you do not recall starting
another test run, the busy PID is likely a stale
`xcodebuild`/`testmanagerd`/`XCTRunner` from a prior timeout-killed
run — see Recovery below.

## Agent session guardrails

**Prevention**:

- Always pass an explicit bash `timeout` — the default 120s is too
  short. Guideline: `180000` (single suite) / `600000` (full unit
  suite) / `900000` (with UI tests).
- For runs expected to exceed 5 minutes, prefer
  `run_in_background: true` and poll with Monitor / BashOutput.
- Narrow scope with `-only-testing PasturaTests/<Suite>` whenever
  possible.

**Recovery (hang or stalled retry)**:

- Bash `timeout` kills the shell wrapper but NOT spawned
  `xcodebuild` / `testmanagerd` / `XCTRunner` processes — they keep
  the simulator busy and subsequent runs queue behind them.
- Before killing, read full command lines so you do not clobber a
  concurrent-worktree run:
  `pgrep -af "xcodebuild|XCTRunner|testmanagerd"`.
- If all listed processes belong to your session:
  `pkill -f "xcodebuild test"`, then
  `xcrun simctl shutdown "$(echo "$DEST" | sed -n 's/.*id=//p')"`.
- UI test
  `FBSOpenApplicationServiceErrorDomain Code=1 — com.tyabu12.PasturaUITests.xctrunner`
  → `xcrun simctl erase <UDID>` + retry **once**. Persistent failures
  are real bugs (signing / plist / app-state regression), not flakes.
