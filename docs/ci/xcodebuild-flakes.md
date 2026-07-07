# xcodebuild / CI flake catalog & session recovery

On-demand reference extracted from `.claude/rules/xcodebuild-cli.md`
(context-budget — rare-event walkthroughs and the flake-signature
catalog are human-debugging reference, not next-decision material, so
they live here rather than in the always-loaded rule). The rule keeps
the lead claims + the key inline commands + a pointer to this file.

## Recovery (hang or stalled retry)

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
  `FBSOpenApplicationServiceErrorDomain Code=1 — app.pastura.PasturaUITests.xctrunner`
  → `xcrun simctl erase <UDID>` + retry **once**. Persistent failures
  are real bugs (signing / plist / app-state regression), not flakes.

## CI flake catalog (auto-retried by `ci-retry.yml`)

`.github/workflows/ci-retry.yml` auto-retries failed UI test jobs
(workflow_run-triggered; max 3 attempts on main / 2 on PR; gated on
ui-test failure). For known flake classes below, first check
`run_attempt` on the failed CI run before manual intervention. Auto-retry
covers all three; manual `gh run rerun --failed <run_id>` is only needed
if auto-retry exhausted.

| Class | Failure message | Distinguishing signal | xcodebuild built-in retry recovers? |
|---|---|---|---|
| **Within-process clone cascade** | 200-330 tests "failed (0.000 seconds)" same simulator clone PID | Single-PID, no assertion output, no wall-clock | Yes (passes on retry) |
| **App-launch timeout** | `Failed to launch ...: Timed out while launching application via Xcode` / `Timed out while requesting launch progress` | Other UI tests in same run launched the same `Pastura.app` and passed | **No** — retry exhausts at launch phase; xcresult shows "Failed after 2 retries" |
| **Runner-init Accessibility** | `Test runner failed to initialize ... Timed out while loading Accessibility` | xcresult: 0 test cases executed (runner never booted); zero `Test case ... passed` lines | **No** — `-retry-tests-on-failure -test-iterations 2` presupposes runner booted |

**All three are distinct from the `FBSOpenApplicationServiceErrorDomain
Code=1` pattern documented in § Recovery above
(`simctl erase <UDID>` + retry once on the FBSOpen marker).** That pattern
is the runner already booted + app explicitly rejected, recoverable by
erasing the simulator. The three flakes above are infra-pressure failures
on the GHA macos-26 runner (suspected root cause: Accessibility framework
load + within-process clone pressure under constrained VM).

### XCUITest idle-stall on continuous animations (slowness, not a retry-flake)

When the `ui-test` job is slow (heavy tests 300–400 s) but the same tests run ~25 s
locally, suspect **idle-stall**: XCUITest waits for the app to reach "idle" (no continuous
`CAAnimation`) before each query, so indeterminate `ProgressView()`,
`.symbolEffect(…, options: .repeating)`, `.repeatForever` stall every query. Manifests on
the GPU-less CI sim only (Mac GPU masks it locally) — **local before/after can't validate;
use a draft-PR CI run**. Suppress under `--ui-test` (`UITestMode.isActive` →
`IdleFriendlyProgressView` + `symbolEffect(isActive:)` guards). **Cap-tuning gotcha**: legit
durations overlap the stall range, so a single tight `-default-test-execution-time-allowance`
false-kills slow-by-design tests (opt out via per-test `executionTimeAllowance`).

### When to escalate

- **First failed CI run**: check `run_attempt` — if 1, let `ci-retry.yml`
  fire automatically (no manual action).
- **After auto-retry exhausted** (attempt 3 on main / 2 on PR): manually
  `gh run rerun --failed <run_id>` once.
- **If THAT also fails the same way**: escalate to real-bug investigation.
  Real signing / Info.plist / app-init regressions fail across runs with
  the SAME failure message at the SAME stage — they do NOT recover from
  `gh run rerun` without a code change.

If ALL UI tests in a run fail at launch (not just some), treat as a real
bug rather than flake.

Tracked indirectly by [#189](https://github.com/tyabu12/pastura/issues/189)
(parallel-testing OOM cascade — related runner-pressure pattern, separate
root cause). Auto-retry workflow: `.github/workflows/ci-retry.yml`. Local
re-run prescription for within-process clone class: "Re-run once before
diagnosing — do NOT 'fix' the listed tests."
