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

### Re-passing wrapper-supplied flags

The wrapper auto-supplies `-scheme`, `-project`, `-destination`, and
`-derivedDataPath`. Their override semantics differ:

| Flag | Re-pass via `[args]`? |
|------|------------------------|
| `-scheme` | **Rejected** — `error: option '-scheme' may only be provided once` |
| `-project` | **Rejected** — same |
| `-derivedDataPath` | **Rejected** — same |
| `-destination` | **Accepted but ADDITIVE, not last-wins** — see below |

xcodebuild prints the rejection error followed by its full usage page
(exit 64). The error line lands between the wrapper's xtrace and the
usage page, so it is easy to miss — the failure looks like a wrapper
bug. Forward only what the wrapper does not supply: typically just
`-only-testing` / `-skip-testing` / `--tail N` (the last is wrapper-only,
consumed before xcodebuild is invoked).

**`-destination` is additive for `test`, NOT last-wins.** xcodebuild runs
the suite on **every** `-destination` given. The wrapper already supplies its
own `-destination` (from `sim-dest.sh`, default iPhone 17 Pro), so appending a
second one runs the tests on **both** devices — and a failure on the extra
device aborts the whole run (exit 65). Do **not** re-pass `-destination` to
"override" the wrapper's simulator. To pin a **single** simulator, set the
`PASTURA_SIM_NAME` env var (honored by `sim-dest.sh`), which replaces the
priority list with that one device so the wrapper emits the right lone
`-destination`. `export` it on its own line — the leading-assignment form
(`PASTURA_SIM_NAME=… scripts/xcodebuild.sh …`) trips the allowlist approval
prompt, per § "Canonical invocation":

```bash
export PASTURA_SIM_NAME="iPhone 17 Pro Max"
scripts/xcodebuild.sh test …
```

(`scripts/store-shots.sh` uses this `export` form to force the 6.9″ device for
App Store screenshots.)

## When to use what

| Scope | Command |
|---|---|
| TDD red/green (single class) | `scripts/xcodebuild.sh test -only-testing PasturaTests/<Class>` |
| Pre-PR full local run | `scripts/xcodebuild.sh test` |
| Build only (no tests) | `scripts/xcodebuild.sh build` |
| Cap output for context-window budget | `scripts/xcodebuild.sh <cmd> --tail N [args]` |
| CI full run | `.github/workflows/ci.yml` (bypasses wrapper) |

Skip UI tests with `-skip-testing:PasturaUITests` when the change
does not touch UI (UI tests are not required for MVP). Integration
tests (Ollama / Llama) require their `*_INTEGRATION` env var enabled
**in the scheme** (`LaunchAction > EnvironmentVariables` inherited by
`TestAction` via `shouldUseLaunchSchemeArgsEnv="YES"`). CLI env vars
passed to `scripts/xcodebuild.sh test` (or bare `xcodebuild test`) are
NOT forwarded to the test runner subprocess — that path silently
skips the suite while xcodebuild still prints `TEST SUCCEEDED`.
Toggle in Xcode UI, or temporarily flip `isEnabled="YES"` in the XML
before running — revert before commit.

## --tail (built-in, pipefail-safe)

`--tail N` is a wrapper-only flag. xcodebuild uses single-dash flags
so `--`-prefixed names are unambiguous. Accepted at any position;
last value wins on duplicates. Use this instead of external `| tail`
— external tail defeats `pipefail`, masking failed builds as exit 0.

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
  `Pastura/Pastura/Resources/Localizable.xcstrings` before xcodebuild.
  Opt out with `PASTURA_SKIP_XCSTRINGS_SYNC=1` (already set in the
  pre-commit hook so commits do not mutate the catalog outside the
  staging index). Failures write a sentinel at
  `Pastura/DerivedData/.xcstrings-sync-failed` and return 0 — never
  blocks build. Stale entries (kept by Apple by design) can be pruned
  manually via `python3 scripts/xcstrings-prune-stale.py` — read
  `.claude/rules/i18n-catalog.md` first (path-scoped to the catalog; a
  script run loads none of it).
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

### Sourcing it in a script clears your `set -e`

`sim-dest.sh` saves the caller's shell options on entry and restores that
saved snapshot on every exit path. In practice this leaves errexit **off**
after the `source` even if you ran `set -e` before it, so later failures
keep running instead of aborting. **Re-assert `set -euo pipefail`
immediately after sourcing.** Only scripts that source `sim-dest.sh`
directly are at risk — child-process invokers (`ui-tour.sh` →
`xcodebuild.sh`) are unaffected. Reference re-assert:
`scripts/motion-capture.sh`.

## Agent session guardrails

**Prevention**:

- Always pass an explicit bash `timeout` — the default 120s is too
  short. Guideline: `180000` (single suite) / `600000` (full unit
  suite) / `900000` (with UI tests).
- For runs expected to exceed 5 minutes, prefer
  `run_in_background: true` and poll with Monitor / BashOutput.
- Narrow scope with `-only-testing PasturaTests/<Suite>` whenever
  possible.

**Recovery (hang or stalled retry)**: a bash `timeout` kills the shell
wrapper but NOT spawned `xcodebuild` / `testmanagerd` / `XCTRunner` —
they keep the simulator busy and later runs queue behind them.
**Read command lines before killing** so you do not clobber a
concurrent-worktree run: `pgrep -af "xcodebuild|XCTRunner|testmanagerd"`;
if all are yours, `pkill -f "xcodebuild test"` then
`xcrun simctl shutdown "$(echo "$DEST" | sed -n 's/.*id=//p')"`. UI-test
`FBSOpenApplicationServiceErrorDomain Code=1` → `xcrun simctl erase <UDID>`
+ retry **once** (persistent = real signing / plist / app-state bug).
A local full-suite UI-test failure at `t = 0.00s` with no `Pastura-*.ips` is
simulator infrastructure, not the app — re-run rather than diagnose.
Full walkthrough: [`docs/ci/xcodebuild-flakes.md`](../../docs/ci/xcodebuild-flakes.md)
§ Recovery / § "Local full-suite flake".

## "Executed 0 tests" in the XCTest stanza is cosmetic for Swift-Testing suites

The XCTest output stanza (`Executed N tests`) counts only `XCTestCase` subclasses — for
Swift-Testing-only files it always prints `Executed 0 tests`, which is **cosmetic, not a
"file not in target" signal**. The real count is in the Swift Testing stanza below
(`✔ Test … passed`, `Test run with N tests …`). Most Pastura tests are Swift Testing.
**Disambiguate a true zero**: `✔` markers / `Test run with N tests` present → normal; absent
→ real bug (file at wrong path / not compiled — cf. the `-only-testing` zero-match trap in
`testing.md`). When filtering output keep the markers:
`grep -E "(error:|Test Suite|Executed|passed|failed|✔ Test|Test run)"`.

## Engine/Models/`SimulationEvent` changes need local `swift build` (harness)

The ADR-013 harness is a SwiftPM package reusing `Models`/`LLM`/`Engine`, built by
`swift build` / `swift test` — NOT by `scripts/xcodebuild.sh` or the pre-commit hook (iOS
app target only). So a change to a `SimulationEvent` case (or any harness-reused Engine/
Models source) can pass the full xcodebuild suite + pre-commit locally and still break the
CI "Harness package build" job — `EventLineMapper.swift` has an intentional no-`default:`
exhaustive switch (compile-time canary). **Apply**: on any such change, run `swift build`
from the repo root before push and map the new event in `EventLineMapper` (`nil` for
internal/persistence events). See ADR-013.

## Compile-checking device-only (`#if !targetEnvironment(simulator)`) code

`#if !targetEnvironment(simulator)` blocks (e.g. `SettingsView` model-management UI,
`ModelSettingsRow`) are excluded from the simulator build — which is what
`scripts/xcodebuild.sh build`, `scripts/ui-tour.sh`, and CI all use, so a compile error OR
layout regression there ships unseen. Compile-check without provisioning:
`scripts/xcodebuild.sh build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
(wrapper forwards both trailing args; signing is skipped, and Swift compiles before signing
so `** BUILD SUCCEEDED **` confirms the block compiles). **Layout/visual** still needs a
real device — flag device-QA explicitly in PRs touching these blocks.

## Fresh worktree's first build can fail SPM resolution (misleading message)

A fresh `/orchestrate` worktree has its own empty `Pastura/DerivedData/`. The first build the
pre-commit hook triggers (any build-relevant path — `scripts/**` counts per
`precommit-gate-classify.sh`) can fail at SPM resolution with a trailing
`Build failed. Fix compile errors before committing.` — **misleading**: the real cause is
unresolved SPM working copies, not a compile error. Fix once, then re-commit:
`xcodebuild -resolvePackageDependencies -project Pastura/Pastura.xcodeproj -scheme Pastura -derivedDataPath Pastura/DerivedData`.
Distinct from the harness `swift build` entry above (that's the SwiftPM *harness*).

## CI flake catalog

CI UI-test failures cluster into known flake classes — within-process
clone cascade (retired post-#1053, see below), app-launch timeout,
runner-init Accessibility, and XCUITest idle-stall — auto-retried by
`.github/workflows/ci-retry.yml`
(max 3 attempts on main / 2 on PR, ui-test-failure-gated).
**Check `run_attempt` on the failed run before intervening**: if 1, let
auto-retry fire; only after it exhausts do `gh run rerun --failed <run_id>`
once; escalate to real-bug investigation only when the same message recurs
at the same stage across reruns (real signing / Info.plist / app-init
regressions do not self-recover). Flake signatures, distinguishing signals,
the idle-stall `--ui-test` suppression, and the full escalation tree:
[`docs/ci/xcodebuild-flakes.md`](../../docs/ci/xcodebuild-flakes.md).
Runner-pressure tracking: [#189](https://github.com/tyabu12/pastura/issues/189).
Post-#1053 the `ui-test` job runs serialized (`-parallel-testing-enabled NO`,
like `lint-and-test`), which retires the clone-dependent classes
(within-process clone cascade + contention stall) — a recurrence of either
means the flag was dropped, not a new flake.
