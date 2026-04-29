# xcodebuild CLI Rules

Extracted from CLAUDE.md to keep the top-level project file lean. Always-loaded
— see CLAUDE.md "Context-Specific Rules" for the loading-mode rationale.

## Test & Build Execution

All local `xcodebuild test` / `xcodebuild build` invocations — including
the `git commit` pre-commit build hook — go through
`scripts/xcodebuild.sh`. The wrapper sources `sim-dest.sh`, applies the right
flags per subcommand, and streams output directly to the terminal. CI does
NOT use the wrapper — see the table below.

### When to use what

| Scope | Command |
|---|---|
| TDD red/green cycle (single class) | `scripts/xcodebuild.sh test -only-testing PasturaTests/<Class>` |
| Pre-PR full local run | `scripts/xcodebuild.sh test` |
| Build only (no tests) | `scripts/xcodebuild.sh build` |
| Cap output for context-window budget | `scripts/xcodebuild.sh <cmd> --tail N [args]` (built-in flag; preserves xcodebuild's exit code via `pipefail`; use instead of external `\| tail`) |
| CI full run | `.github/workflows/ci.yml` (uses `xcodebuild test ... -parallel-testing-enabled NO` inline; CI's SPM cache key depends on `~/Library/...` so it intentionally bypasses the wrapper — see [#189](https://github.com/tyabu12/pastura/issues/189)) |

### Canonical invocation

**Always invoke via the absolute path resolved by `git rev-parse`:**

```bash
"$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" <subcommand> [--tail N] [args]
```

`--tail N` is a wrapper-only flag (xcodebuild itself uses single-dash
flags, so `--`-prefixed names are unambiguous). Accepted at any position
among the args and consumed before forwarding the rest to xcodebuild;
duplicates follow xcodebuild's own repeated-flag convention (last wins).
See **Running xcodebuild from an agent session** below for when to use it.

This matches `sim-dest.sh`'s convention and is the only form the Bash
allowlist (`Bash("$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh"*)`)
matches. cwd-independent — works correctly from any subdirectory of the
worktree (agent sessions in particular shift cwd often, so relative-path
invocations like `scripts/xcodebuild.sh ...` are NOT allowlisted and would
trigger permission prompts).

The wrapper also resolves `REPO_ROOT` internally (so `-project` and the
`sim-dest.sh` source path are absolute regardless of cwd) — invocation
form and wrapper internals are independently cwd-safe.

### Wrapper behavior

`scripts/xcodebuild.sh` is a thin dispatcher. Args after the subcommand
forward verbatim to xcodebuild via `"$@"`. xcodebuild honors the last value
for repeated single-value flags, so caller passthrough wins on duplicates.

- **`test`**: uses the UDID-pinned simulator (`$DEST` from `sim-dest.sh`)
  and adds `-parallel-testing-enabled NO`. The parallel-OFF flag mirrors
  the CI workaround for the within-process simulator-clone crash cascade
  (200+ tests reporting `failed` at 0.000s on a single clone PID — local
  Apple Silicon reproduces at ~50% on the full suite). Harmless for narrow
  TDD runs since `@Suite(.serialized)` already orders within-suite tests.
  Root-cause work stays in [#189](https://github.com/tyabu12/pastura/issues/189).

- **`build`**: uses `generic/platform=iOS Simulator` (no UDID) and exports
  `PASTURA_SKIP_SIM_WAIT=1` before sourcing `sim-dest.sh` so the
  concurrent-session simulator gate is bypassed. Build artifacts are
  architecturally identical across simulator UDIDs, so booking a specific
  UDID wastes time and reintroduces gate contention. `$DERIVED_DATA` is
  still populated so build output lands in the worktree-local
  `Pastura/DerivedData/` — and since the pre-commit hook now also
  invokes `scripts/xcodebuild.sh build`, its build cache shares the
  same worktree-local path as agent-driven test runs (so post-test
  pre-commit builds hit warm cache).

```bash
# Convenience alias for shell history (or use the full form inline)
xcb="$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh"

# TDD cycle — narrow to one suite for fast iteration
"$xcb" test -only-testing PasturaTests/JSONResponseParserTests

# Pre-PR full local run
"$xcb" test

# Skip UI tests when the change doesn't touch UI code
"$xcb" test -skip-testing:PasturaUITests

# Build only (no tests) — type-check verification after refactor
"$xcb" build

# Cap output for context-window budget — `--tail N` is built-in,
# pipefail-safe (preserves xcodebuild's exit code), and accepted at
# any position. Use instead of external `| tail`.
"$xcb" build --tail 30
"$xcb" test -only-testing PasturaTests/JSONResponseParserTests --tail 80

# Run Ollama integration tests (requires local Ollama with target model pulled)
# Enable OLLAMA_INTEGRATION in scheme: Edit Scheme → Run → Environment Variables → toggle ON
"$xcb" test -only-testing PasturaTests/OllamaIntegrationTests
# These tests are automatically skipped when OLLAMA_INTEGRATION is not enabled in the scheme.
```

> Agents that don't use the `xcb` alias should expand the full
> `"$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" ...` form
> on every call — the allowlist match is on the literal string.

### DerivedData location

`sim-dest.sh` exports `DERIVED_DATA` pointing at `Pastura/DerivedData/` inside
the current worktree. The wrapper passes `-derivedDataPath "$DERIVED_DATA"`
for both subcommands so the CLI matches the Xcode.app Workspace-relative
layout configured in `project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings`.
This keeps GUI and CLI builds sharing one cache per worktree and makes
`git worktree remove` auto-clean all build artifacts. Two gotchas (relevant
when invoking xcodebuild manually outside the wrapper):

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
cascades. The match pattern intentionally requires `,id=` so build-only
invocations (which use `generic/platform=iOS Simulator`, no UDID) bypass
the gate — `scripts/xcodebuild.sh build` (and therefore the pre-commit
hook, which now invokes the wrapper) benefits from this exclusion.

`scripts/xcodebuild.sh build` additionally exports `PASTURA_SKIP_SIM_WAIT=1`
before sourcing `sim-dest.sh`, providing belt-and-suspenders gate skip even
if the destination check ever shifts.

Override with `PASTURA_SKIP_SIM_WAIT=1 source scripts/sim-dest.sh ...` when
NOT using the wrapper:

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

- Narrow scope whenever possible —
  `"$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test -only-testing PasturaTests/<Suite>`.
- If the change doesn't touch UI code, add `-skip-testing:PasturaUITests`
  (UI tests are not required for MVP; CI will still cover them).
- Always pass an explicit bash `timeout` — the default 120s is shorter
  than even a focused suite. Guideline: `timeout: 180000` (3 min) for a
  single suite, `timeout: 600000` (10 min) for the full unit suite,
  `timeout: 900000` (15 min) when UI tests are included.
- For runs expected to exceed 5 minutes, prefer `run_in_background: true`
  and poll with Monitor / BashOutput rather than blocking the session.
- For context-window-capped output, prefer the built-in `--tail N`
  flag over an external `| tail`:
  `"$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test ... --tail 80`.
  The flag is pipefail-safe (preserves xcodebuild's exit code), accepts
  its value anywhere among the args, and suppresses `set -x` xtrace so
  the visible window stays focused on build output. External `| tail`
  defeats `pipefail` — a failed build reports `exit code 0` to the
  harness, silently masking failures (see memory
  `feedback_xcodebuild_pipefail.md` for the original incident).
- For pattern filtering, external `| grep` is still acceptable, but
  note that any external pipe (grep, tail, head) replaces the wrapper's
  exit code with the last command's. Treat the harness exit-code
  notification as informational only when piping externally — verify
  success by grepping the output for `** BUILD SUCCEEDED **` /
  `** TEST SUCCEEDED **` (or the corresponding FAILED markers), or use
  caller-side `set -o pipefail`. When the SUCCEEDED marker has been
  trimmed off entirely (long suites past `--tail` budget), extract the
  verdict from the xcresult bundle:
  `xcrun xcresulttool get test-results summary --path "$XCRESULT" --format json`.

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
