# xcodebuild CLI Rules

Local `xcodebuild test` / `build` — including the git pre-commit hook — go through `scripts/xcodebuild.sh`. It supplies scheme, project, destination, DerivedData (worktree-local `Pastura/DerivedData/`), and the simulator gate; it also **mutates** `Localizable.xcstrings` (`xcstringstool extract` + `sync`) before every run — `PASTURA_SKIP_XCSTRINGS_SYNC=1` opts out, and the pre-commit hook sets it, so a catalog left dirty by an earlier plain run is what a later `git add -A` sweeps in. It **prints its own reason** whenever it rejects a flag, waits on a busy simulator, or warns about an ignored env var — so read its output before working around it.

## Invocation

Run from the repository root, **bare and cwd-relative**:

```bash
scripts/xcodebuild.sh test [-only-testing PasturaTests/<Class>] [-skip-testing:PasturaUITests] [--tail N]
scripts/xcodebuild.sh build
scripts/xcodebuild.sh build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO   # compile-check device-only code
```

The allowlist entries `Bash(scripts/xcodebuild.sh*)` and `Bash(source scripts/sim-dest.sh)` are exact-prefix literals. **These shapes miss them and raise an approval prompt, which kills an unattended run before the tool executes:** variable expansion (`"$xcb" …`), a `cd … &&` prefix, a leading env-var assignment (`PASTURA_SKIP_XCSTRINGS_SYNC=1 scripts/…`), an absolute path, and any `$(…)` in the command ([claude-code#31373](https://github.com/anthropics/claude-code/issues/31373)). The wrapper never needs a `cd`.

`--tail N` is the wrapper's pipefail-safe output cap — any external pipe (`| tail`, `| grep`) replaces the wrapper's exit code with the reader's, so a failed build reads as exit 0; grep for the `** BUILD SUCCEEDED **` / `FAILED` markers or set `pipefail` caller-side. `TEST SUCCEEDED` does not mean tests ran: confirm the `✔ Test` / `Test run with N tests` markers.

## Timeouts

Always pass an explicit bash `timeout`: `180000` (single suite) / `600000` (full unit suite) / `900000` (with UI tests). `test` can block up to 15 minutes behind another session's run — the wrapper announces the wait and the bypass. A bash timeout kills the shell, not the spawned `xcodebuild` / `testmanagerd`; read their command lines before killing anything (a sibling worktree's run looks identical): `docs/ci/xcodebuild-flakes.md` § Recovery.

## Engine / Models / `SimulationEvent` changes also need `swift build`

The ADR-013 harness (`tools/harness`) is a SwiftPM package reusing `Models` / `LLM` / `Engine`, built by `swift build` from the repo root — not by the wrapper or the pre-commit hook. Map any new `SimulationEvent` case in its `EventLineMapper` (`nil` for internal events); its switch is deliberately `default:`-less.

## A stale SPM resolution reads as a compile error

The wrapper resolves packages only when DerivedData holds none. A stale or partial resolution makes the pre-commit hook report `Build failed. Fix compile errors before committing.` for a compile error that does not exist. Recover with the raw command below — `-derivedDataPath` takes a **space**, not `=`; the `=` form is silently ignored and resolves into the wrong DerivedData:

```bash
xcodebuild -resolvePackageDependencies -project Pastura/Pastura.xcodeproj -scheme Pastura -derivedDataPath Pastura/DerivedData
```

CI flake classes (launch timeout, runner-init Accessibility, idle stall) are auto-retried by `ci-retry.yml`; check `run_attempt` before intervening — `docs/ci/xcodebuild-flakes.md`.
