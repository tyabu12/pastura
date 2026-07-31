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

## Local full-suite flake: simulator infrastructure crash before app launch

**Local only** — this class has nothing to do with `ci-retry.yml` or the GHA
catalog below. It fires during a local `scripts/xcodebuild.sh test` full run and
is filed here, next to § Recovery, because that is where a local debugging
session arrives.

Observed three times during #1334, and re-diagnosed all three — twice while
suspecting a real regression, because the same test failed at the same point
across consecutive full-suite runs, which § "When to escalate" gives as the
signal to *stop* treating something as a flake.

**Signature** (all five together; any one alone is not enough):

- `EditorReloadTests.testEditorSavePopsAndReloadsHome` fails at **`t = 0.00s`**
  with `[XPCErrors] [C:N] Error received: Connection interrupted` — *before the
  app launches*, so no app-side change can reach it
- followed by `Restarting after unexpected exit, crash, or test timeout`
- **no `Pastura-*.ips`** in `~/Library/Logs/DiagnosticReports/`; instead
  `SimRenderServer` (`EXC_BREAKPOINT` / `SIGTRAP`) and `testmanagerd` crash logs
  at the same timestamp
- passes in isolation: `scripts/xcodebuild.sh test -only-testing PasturaUITests/EditorReloadTests`
- observed each time on the test that runs immediately after
  `DeepLinkTabRoutingUITests` — a position, not a property of the test

**Action**: re-run the full suite. Confirm with the `-only-testing` run above if
you want a second data point first. Do **not** change `EditorReloadTests` — it is
the position in the sequence that is being hit, so editing the test moves the
failure rather than fixing it.

**Why the recurrence rule does not apply.** § "When to escalate" and
`.claude/rules/xcodebuild-cli.md` § "CI flake catalog" both say to escalate when
the same message recurs at the same stage across reruns. Both are written about
**CI reruns** (`run_attempt`, `gh run rerun --failed`), and every cause they
enumerate is app-side — signing, `Info.plist`, app-init regressions. Generalizing
that rule to a local full-suite run misfires when the failure *precedes* app
launch: nothing app-side is running yet, so recurrence carries no information
about the app. **Absence of a `Pastura-*.ips` is what settles it** — the mirror of
the AttributeGraph render-crash class, where `.claude/rules/swiftui-traps.md`
points at those same frames because the crash *is* in the app.

## CI flake catalog (auto-retried by `ci-retry.yml`)

`.github/workflows/ci-retry.yml` auto-retries failed UI test jobs
(workflow_run-triggered; max 3 attempts on main / 2 on PR; gated on
ui-test failure). For known flake classes below, first check
`run_attempt` on the failed CI run before manual intervention. Auto-retry
covers all three; manual `gh run rerun --failed <run_id>` is only needed
if auto-retry exhausted.

| Class | Failure message | Distinguishing signal | xcodebuild built-in retry recovers? |
|---|---|---|---|
| **Within-process clone cascade** _(retired post-#1053 — serialization removed clones)_ | 200-330 tests "failed (0.000 seconds)" same simulator clone PID | Single-PID, no assertion output, no wall-clock | Yes (passes on retry) |
| **App-launch timeout** | `Failed to launch ...: Timed out while launching application via Xcode` / `Timed out while requesting launch progress` | Other UI tests in same run launched the same `Pastura.app` and passed | **No** — retry exhausts at launch phase; xcresult shows "Failed after 2 retries" |
| **Runner-init Accessibility** | `Test runner failed to initialize ... Timed out while loading Accessibility` | xcresult: 0 test cases executed (runner never booted); zero `Test case ... passed` lines | **No** — `-retry-tests-on-failure -test-iterations 2` presupposes runner booted |

**All three are distinct from the `FBSOpenApplicationServiceErrorDomain
Code=1` pattern documented in § Recovery above
(`simctl erase <UDID>` + retry once on the FBSOpen marker).** That pattern
is the runner already booted + app explicitly rejected, recoverable by
erasing the simulator. The three flakes above are infra-pressure failures
on the GHA macos-26 runner (suspected root cause: Accessibility framework
load + within-process clone pressure under constrained VM).

### Clone-contention transition stall (retired by #1053 serialization)

A fourth, distinct pre-#1053 class: **specific** UI tests fail on a legit
`waitForExistence` timeout — a navigation/transition sentinel that never
appears (`"ScenarioDetailView did not appear"`, a post-edge-swipe pop that
does not return within its window) — while **another** test in the *same*
run passes but takes 3× its normal wall-clock (a ~72 s suite crawling to
~3 min). The log shows `Clone 1` and `Clone 2` of the simulator active
simultaneously.

- **Distinguishing signal**: real wall-clock elapsed (not the 0.000 s
  cascade), launch succeeded (not the app-launch timeout), and the
  whole-runner slowdown hits *passing* tests too — the tell is a passing
  test that is inexplicably slow, not just the failing one.
- **Auto-retry recovers?** Unreliably, and `ci-retry.yml` may not either:
  run `29058528291` failed the same `InFlightIndicatorReconnectUITests` on
  attempt 1 **and** attempt 3, exhausting the budget red.
- **Root cause**: the `ui-test` job ran 2 simulator clones in parallel
  (scheme `parallelizable="YES"`) while `lint-and-test` already serialized
  (#189). Two simulators + two apps + two runners contending on the ~7 GB
  GPU-less macos-26 runner stall software-rendered transitions for tens of
  seconds, breaching test waits.
- **Fix (#1053)**: `-parallel-testing-enabled NO` on the `ui-test`
  xcodebuild invocation serializes onto the single pre-booted simulator.
  This structurally removes the contention **and** retires the
  **within-process clone cascade** row above (also clone-dependent), so
  both are historical on `main` post-#1053 — treat a recurrence as a sign
  the flag was dropped. Companion test changes: `InFlightIndicatorReconnectUITests`
  `executionTimeAllowance` 600→300 (additive under serial; bounds the
  timeout-kill tail under the 30-min ceiling `ci-retry.yml` will not retry)
  and a one-shot `edgeSwipeBack` retry for the orthogonal dropped-gesture
  class.

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
