# xcodebuild CLI Rules

Always-loaded — see CLAUDE.md "Context-Specific Rules" for the
loading-mode rationale.

Local `xcodebuild test` / `build` invocations — including the `git commit`
pre-commit hook — go through `scripts/xcodebuild.sh`. CI bypasses the wrapper
([#189](https://github.com/tyabu12/pastura/issues/189)).

## Canonical invocation

**Run from the repository root, bare and cwd-relative:**

```bash
scripts/xcodebuild.sh <subcommand> [--tail N] [args]
```

Allowlist: `Bash(scripts/xcodebuild.sh*)` and `Bash(source scripts/sim-dest.sh)`
— **exact-prefix literal matches**, so four shapes miss them and raise an
approval prompt, which on an unattended run kills that run rather than teaching
it anything: variable expansion (`"$xcb" …`), `cd … && scripts/xcodebuild.sh …`,
a leading env-var assignment (`PASTURA_SKIP_XCSTRINGS_SYNC=1 scripts/…`), and an
absolute path. The wrapper resolves `REPO_ROOT` itself, so it never needs a `cd`.
Scope that to these two entries, **not** to the matcher generally — `git -C
<path> diff` has been observed to run unprompted under an equally bare
`Bash(git diff*)`. A `$(…)`-bearing form prompts whatever the allowlist says
([claude-code#31373](https://github.com/anthropics/claude-code/issues/31373),
OPEN); `.claude/settings.json` hooks keep `$()` on purpose — they run as direct
shell processes and never reach the permission gate.

Forward only what the wrapper does not supply — typically `-only-testing` /
`-skip-testing`, plus the wrapper-only `--tail N`. It rejects a re-passed
`-scheme` / `-project` / `-destination` / `-derivedDataPath` with the reason per
flag, ahead of the simulator gate. To pin **one** simulator for `test`:

```bash
export PASTURA_SIM_NAME="iPhone 17 Pro Max"
scripts/xcodebuild.sh test …
```

## When to use what

| Scope | Command |
|---|---|
| TDD red/green (single class) | `scripts/xcodebuild.sh test -only-testing PasturaTests/<Class>` |
| Pre-PR full local run | `scripts/xcodebuild.sh test` |
| Build only (no tests) | `scripts/xcodebuild.sh build` |
| Compile-check device-only code | `scripts/xcodebuild.sh build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` — see `build-traps.md` |
| Cap output for context-window budget | `scripts/xcodebuild.sh <cmd> --tail N [args]` |
| CI full run | `.github/workflows/ci.yml` (bypasses wrapper) |

Skip UI tests with `-skip-testing:PasturaUITests` when the change does not touch
UI (UI tests are not required for MVP). Integration suites gate on a
`*_INTEGRATION` env var read by the **test runner**, which inherits nothing from
the CLI — so a CLI-set one skips the suite and still prints `TEST SUCCEEDED`
(the wrapper warns if it sees one exported). Set it in the scheme, or flip
`isEnabled="YES"` in the scheme XML and **revert before commit**; each
integration suite's doc comment carries the procedure.

## --tail (built-in, pipefail-safe)

`--tail N` is a wrapper-only flag, accepted at any position (last value wins).
Use it instead of an external `| tail`, which defeats `pipefail` and reports a
**failed build as exit 0**.

External `| grep` is fine for filtering, but the pipe replaces the wrapper's exit
code with grep's — verify by grepping for `** BUILD SUCCEEDED **` /
`** TEST SUCCEEDED **` (or the `FAILED` markers), or set `pipefail` caller-side.
When the marker was trimmed off entirely:
`xcrun xcresulttool get test-results summary --path "$XCRESULT" --format json`.

## Wrapper behavior

- **`test`**: UDID-pinned simulator + `-parallel-testing-enabled NO` ([#189](https://github.com/tyabu12/pastura/issues/189)).
- **`build`**: `generic/platform=iOS Simulator`, no UDID booking; it exports
  `PASTURA_SKIP_SIM_WAIT=1`, so the gate below never applies to a build.
- **Auto-sync**: both subcommands **mutate** `Localizable.xcstrings`
  (`xcstringstool extract` + `sync`) before xcodebuild — opt out with
  `PASTURA_SKIP_XCSTRINGS_SYNC=1` (already set in the pre-commit hook, so a
  commit does not mutate the catalog outside its staging index). A sync failure
  is advisory, never a build failure. Pruning stale entries is manual and
  separate: read `.claude/rules/i18n-catalog.md` first (a script run loads none
  of it), then `python3 scripts/xcstrings-prune-stale.py`.
- **DerivedData**: worktree-local `Pastura/DerivedData/`, so
  `git worktree remove` cleans it.

## Concurrent-session simulator gate

`test` blocks at `source scripts/sim-dest.sh` while another `xcodebuild test`
with a `,id=<UDID>` destination runs on this machine — **up to 15 minutes**, so
size the bash `timeout` for it and do not kill a run that merely looks stuck. It
announces the wait, naming the busy PIDs and the bypass variable. `build` never
waits (`generic/platform=…`, no UDID).

Manual override for genuine parallelism, or for `simctl` /
`-showBuildSettings` inspection. This exact form misses the allowlist and
prompts, by design:

```bash
PASTURA_SKIP_SIM_WAIT=1 source scripts/sim-dest.sh
```

A gate that times out when you started no other run is a stale
`xcodebuild`/`testmanagerd`/`XCTRunner` — see § Agent session guardrails.

## Agent session guardrails

**Prevention**:

- Always pass an explicit bash `timeout` — the default 120s is too
  short. Guideline: `180000` (single suite) / `600000` (full unit
  suite) / `900000` (with UI tests).
- For runs expected to exceed 5 minutes, prefer
  `run_in_background: true` and poll with Monitor / BashOutput.
- Narrow scope with `-only-testing PasturaTests/<Suite>` whenever
  possible.

**Recovery (hang or stalled retry)**: a bash `timeout` kills the shell wrapper
but NOT the spawned `xcodebuild` / `testmanagerd` / `XCTRunner`, which keep the
simulator busy so later runs queue behind them. **Read their command lines before
killing anything** — a concurrent worktree's run looks identical. Inspect / kill /
`simctl erase` steps, the UI-test launch-failure marker, and the local
`t = 0.00s` failure that is simulator infrastructure rather than the app:
[`docs/ci/xcodebuild-flakes.md`](../../docs/ci/xcodebuild-flakes.md)
§ Recovery / § Local full-suite flake.

## Engine/Models/`SimulationEvent` changes need local `swift build` (harness)

The ADR-013 harness is a SwiftPM package reusing `Models`/`LLM`/`Engine`, built by
`swift build` — **not** by `scripts/xcodebuild.sh` or the pre-commit hook, which
cover the iOS app target only. So such a change passes the full local suite and
still breaks CI's "Harness package build". **Apply**: run `swift build` from the
repo root before push, and map any new `SimulationEvent` case in the harness's
`EventLineMapper` (`nil` for internal / persistence events) — its switch is
deliberately `default:`-less as a compile-time canary. See ADR-013.

## A stale SPM resolution reads as a compile error

The wrapper resolves SPM packages when this DerivedData holds **none**, so a fresh
worktree repairs itself. A resolution that is *stale* rather than absent (a
`Package.resolved` bump, a moved revision) is not covered: the pre-flight stays
quiet and the pre-commit hook reports `Build failed. Fix compile errors before
committing.` for a compile error that does not exist. Recover, then re-commit:

```bash
xcodebuild -resolvePackageDependencies -project Pastura/Pastura.xcodeproj -scheme Pastura -derivedDataPath Pastura/DerivedData
```

## CI flake catalog

CI UI-test failures cluster into known classes — app-launch timeout, runner-init
Accessibility, and XCUITest idle-stall — auto-retried by
`.github/workflows/ci-retry.yml`. A fourth, **within-process clone cascade, is
retired**: #1053 made the `ui-test` job serialized, so a recurrence of it (or of
the contention stall) means `-parallel-testing-enabled NO` was dropped from that
job, not that a flake came back.

**Check `run_attempt` on the failed run before intervening**: if 1, let auto-retry
fire; only after it exhausts, `gh run rerun --failed <run_id>` once; escalate to
real-bug investigation only when the same message recurs at the same stage across
reruns (signing / Info.plist / app-init regressions do not self-recover).
Signatures, distinguishing signals and the escalation tree:
[`docs/ci/xcodebuild-flakes.md`](../../docs/ci/xcodebuild-flakes.md).
