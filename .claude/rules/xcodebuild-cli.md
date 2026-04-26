# xcodebuild CLI Rules

Extracted from CLAUDE.md to keep the top-level project file lean. Always-loaded
— see CLAUDE.md "Context-Specific Rules" for the loading-mode rationale.

## Test Execution

### When to use what

| Scope | Command | Parallel testing |
|---|---|---|
| TDD red/green cycle (single class / method) | `xcodebuild test ... -only-testing PasturaTests/<Class>` (direct) | n/a (single class — no benefit) |
| Pre-PR full local run | `scripts/test-full.sh` | **OFF** (forced — see below) |
| CI full run | `.github/workflows/ci.yml` | **OFF** (already applied — see [#189](https://github.com/tyabu12/pastura/issues/189)) |

`scripts/test-full.sh` is a thin wrapper that sources `sim-dest.sh` and runs
`xcodebuild test` with `-parallel-testing-enabled NO` injected before any
forwarded args. It mirrors the CI workaround for the within-process
simulator-clone crash cascade — local Apple Silicon runs reproduce the
cascade at ~50% frequency on the full suite, so any pre-PR full run should
go through the wrapper. Root-cause investigation continues in
[#189](https://github.com/tyabu12/pastura/issues/189); this is the
symptom-level mitigation. TDD-focused runs (`-only-testing PasturaTests/<Class>`)
are unaffected by the cascade and should bypass the wrapper for speed.

```bash
source "$(git rev-parse --show-toplevel)/scripts/sim-dest.sh"

# Pre-PR full local run (parallel testing forced OFF)
scripts/test-full.sh
# Forwards extra args verbatim — narrow scope, skip UI tests, etc.
scripts/test-full.sh -skip-testing:PasturaUITests

# Run specific test class (TDD cycle — direct invocation, no wrapper)
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
  -destination "$DEST" -derivedDataPath "$DERIVED_DATA" \
  -only-testing PasturaTests/JSONResponseParserTests

# Run Ollama integration tests (requires local Ollama with target model pulled)
# Enable OLLAMA_INTEGRATION in scheme: Edit Scheme → Run → Environment Variables → toggle ON
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
  -destination "$DEST" -derivedDataPath "$DERIVED_DATA" \
  -only-testing PasturaTests/OllamaIntegrationTests
# These tests are automatically skipped when OLLAMA_INTEGRATION is not enabled in the scheme.
```

### DerivedData location

`sim-dest.sh` exports `DERIVED_DATA` pointing at `Pastura/DerivedData/` inside
the current worktree. Always pass `-derivedDataPath "$DERIVED_DATA"` to
`xcodebuild` so the CLI matches the Xcode.app Workspace-relative layout
configured in `project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings`.
This keeps GUI and CLI builds sharing one cache per worktree and makes
`git worktree remove` auto-clean all build artifacts. Two gotchas:

- **Pass `-derivedDataPath` with a space**, not `=`. The `=` form is silently
  ignored by `xcodebuild` (known since Xcode 15.4).
- **CI is intentionally left on the default `~/Library/...` path** so its
  existing SPM cache (`actions/cache` keyed on that path) keeps hitting. If
  CI ever starts passing `-derivedDataPath`, update both cache paths in
  `.github/workflows/ci.yml` in the same PR.

### Concurrent-session simulator gate

`sim-dest.sh` blocks at `source` time if another `xcodebuild test` with a
UDID-pinned iOS Simulator destination (`...,id=<UDID>`) is already running
on this machine — poll every 5s, jitter 1.0–5.0s before claiming, 15-min
timeout. This avoids same-UDID clone/boot/teardown collisions across
concurrent worktree sessions, which otherwise produce 200+ 0.000s "failed"
cascades. The match pattern intentionally requires `,id=` so the pre-commit
`xcodebuild build -destination 'generic/platform=iOS Simulator'` hook does
not trigger the gate (build-only invocations don't book a simulator).

Override with `PASTURA_SKIP_SIM_WAIT=1 source scripts/sim-dest.sh ...`:

- when intentionally running parallel suites on distinct simulators, or
- when sourcing only to inspect `$DEST` (e.g., for `xcrun simctl` /
  `xcodebuild -showBuildSettings`) without running tests.

If the gate consistently times out and you don't recall starting another
test run, the busy PID is likely a stale `xcodebuild`/`testmanagerd`/
`XCTRunner` from a prior timeout-killed run — see **Recovery** below for
the `pgrep` + `pkill` flow. The timeout error message itself includes
the recovery commands.

### Running xcodebuild from an agent session

`xcodebuild test` takes minutes. A few operational guardrails to avoid
burning wall-clock and orphaning processes:

**Prevention (do this up-front):**

- Narrow scope whenever possible — `-only-testing PasturaTests/<Suite>`.
- If the change doesn't touch UI code, add `-skip-testing:PasturaUITests`
  (UI tests are not required for MVP; CI will still cover them).
- Always pass an explicit bash `timeout` — the default 120s is shorter
  than even a focused suite. Guideline: `timeout: 180000` (3 min) for a
  single suite, `timeout: 600000` (10 min) for the full unit suite,
  `timeout: 900000` (15 min) when UI tests are included.
- For runs expected to exceed 5 minutes, prefer `run_in_background: true`
  and poll with Monitor / BashOutput rather than blocking the session.
- When piping through `tail` (e.g. `xcodebuild ... 2>&1 | tail -80`), the
  pipe's exit code is `tail`'s, not `xcodebuild`'s — a failed build reports
  `exit code 0`. Grep the tailed output for `** BUILD|TEST SUCCEEDED/FAILED **`
  or `xcodebuild: error:` before trusting the harness exit code, or use
  `set -o pipefail`. When the SUCCEEDED marker has been trimmed off entirely,
  extract the verdict from the xcresult bundle: `xcrun xcresulttool get test-results summary --path "$XCRESULT" --format json`.

**Recovery (if a run hangs or a retry immediately stalls):**

- The session's bash timeout kills the shell wrapper, but spawned
  `xcodebuild` / `testmanagerd` / `XCTRunner` processes can outlive it
  and keep the simulator destination busy. Subsequent `xcodebuild test`
  calls then queue behind them and appear to hang.
- Before killing, **read the full command lines** so you don't clobber a
  concurrent run from another worktree:
  `pgrep -af "xcodebuild|XCTRunner|testmanagerd"`.
- Only if you're sure every listed process belongs to your session:
  `pkill -f "xcodebuild test"`; then reset the simulator with
  `xcrun simctl shutdown "$(echo "$DEST" | sed -n 's/.*id=//p')"`.
- If UI tests fail with
  `FBSOpenApplicationServiceErrorDomain Code=1 — com.tyabu12.PasturaUITests.xctrunner`,
  try `xcrun simctl erase <UDID>` + retry **once**. Persistent failures
  are real bugs (signing, plist, or app-state regression), not flakes —
  do not swallow them.
