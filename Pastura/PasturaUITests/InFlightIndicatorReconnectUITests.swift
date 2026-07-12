import XCTest

/// Phase B (ADR-017 #682) instant-reconnect across the navigation boundary:
/// leaving a run with "keep running" parks it in memory and surfaces the
/// in-flight indicator across tabs; tapping the indicator re-mounts
/// `SimulationView`, which **adopts** the still-live session rather than
/// starting a fresh run — so the live screen reappears with no
/// "Loading scenario…" reload.
///
/// This is the one nav-boundary regression that pure logic can't reach
/// (`view-testing.md` rule 2): the adopt-on-return is a composition of the
/// session, the tab coordinator, and the view's `.task`. The simulator can't run
/// real inference, so `--ui-test-slow-llm` holds the run in-flight (blocked in
/// the first `generate`) for the whole test; `--ui-test-keep-running` enables
/// the opt-in (a real Bool write — a `-key YES` launch arg lands as a String
/// that `FeatureFlags`' `object(forKey:) as? Bool` reads as nil) so leaving
/// silently parks.
///
/// The slow-LLM hold uses `blockGenerateUntilSignal()` — `generate` blocks on
/// an explicit signal, deliberately NOT `suspendOnControllerAttach` (which
/// *parks* pre-generate): the return path resumes the controller through the
/// `.viewHide` gate, which would let a parked generate exhaust its empty
/// `responses: []` and error. The block is wall-clock-independent, so a slow CI
/// runner can never expire the hold mid-test (#719 replaced the former
/// timing-fragile `generateDelay` sleep); the test never unblocks — tearDown's
/// `terminate()` ends the run. Full rationale lives at
/// `PasturaApp.setupUITestState`.
///
/// Subject to the UI-test flake classes in `.claude/rules/xcodebuild-cli.md`.
@MainActor
final class InFlightIndicatorReconnectUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
    // Opt out of the ci.yml per-test execution-time cap (#728): this test is
    // slow by design — it holds the run in-flight via --ui-test-slow-llm and
    // exercises the park/return flow, taking ~125-225s on CI. That legit range
    // overlaps the infra-flake stall the cap targets, so it gets a dedicated
    // allowance instead of the tighter default. No-op locally where
    // -test-timeouts-enabled is not passed.
    //
    // 300 (was 600): once ui-test serialized (#1053), this test's allowance is
    // additive to the sequential run rather than overlapped with other clones,
    // so a stalled run burning ~2×600s could breach the job's 30-min ceiling
    // (a timed_out conclusion is NOT retried by ci-retry.yml). 300 still clears
    // the observed 225s max with margin while bounding the stall tail.
    executionTimeAllowance = 300
  }

  override func tearDownWithError() throws {
    XCUIApplication().terminate()
  }

  func testIndicatorReturnsToLiveSimulationWithoutReload() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test", "--ui-test-slow-llm", "--ui-test-keep-running"]
    app.launch()

    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    // Reach SimulationView via the one-tap Home-seed row (mirrors BackGestureTests).
    // The `ui_test_home_seed` scenario is installed unconditionally by
    // StubScenarioSeeder on every `--ui-test` launch, so tapping its Home row
    // lands directly on the run-capable ScenarioDetailView — skipping the
    // Browse → gallery → Try-install reach (~70s, the dominant ui-test cost).
    let homeRow = app.buttons["home.scenarioListCell.ui_test_home_seed"]
    XCTAssertTrue(homeRow.waitForExistence(timeout: 5), "Home seed scenario row missing.")
    homeRow.tap()

    let detailList = app.scrollViews["scenarioDetail.list"]
    // 30s (vs the suite's usual 10s): the first navigation render on a cold
    // first simulator clone can stall past 10s under CI runner pressure
    // (app-launch infra-flake class — see .claude/rules/xcodebuild-cli.md
    // § CI flake catalog). waitForExistence returns on appearance, so the
    // sub-second success path is unchanged; this only widens tolerance for the
    // cold-start stall, within this test's dedicated executionTimeAllowance.
    XCTAssertTrue(detailList.waitForExistence(timeout: 30), "ScenarioDetailView did not appear.")
    let runSimulation = app.buttons["scenarioDetail.runSimulationButton"]
    var scrollAttempts = 0
    while !runSimulation.exists && scrollAttempts < 6 {
      detailList.swipeUp()
      scrollAttempts += 1
    }
    XCTAssertTrue(runSimulation.waitForExistence(timeout: 5), "Run Simulation button missing.")
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: runSimulation)
    wait(for: [enabled], timeout: 10)
    runSimulation.tap()

    // The run is now on top and blocked in its first inference (slow LLM).
    let header = app.descendants(matching: .any)["simulation.header.meta"]
    // 30s for the same cold-clone reason as the scenarioDetail.list wait above:
    // this is navigation #2 on the same clone, still inside the cold-start
    // window (see the comment there + .claude/rules/xcodebuild-cli.md).
    XCTAssertTrue(header.waitForExistence(timeout: 30), "SimulationView did not appear.")

    // Leave with "keep running" (Setting on → silent park) via the interactive
    // edge-swipe (bypasses the dialog; coordinate drag required on iOS 17+).
    // Confirm the swipe-back actually popped to ScenarioDetail (its ScrollView
    // is the sentinel), so a failure to pop can't silently pass on a lingering
    // indicator. `edgeSwipeBack` retries a dropped gesture once (#1053).
    edgeSwipeBack(
      in: app,
      until: app.scrollViews["scenarioDetail.list"],
      message: "Leaving the sim did not return to ScenarioDetail.")

    // ScenarioDetail hides the tab bar (contextual action bar, ADR-016
    // § Amendment 2026-07-01), so the tab bar stays hidden here — but the
    // in-flight indicator (a RootTabView overlay, independent of the tab bar)
    // surfaces once the sim is no longer on top.
    let indicator = app.buttons["inFlightSimulationIndicator"]
    XCTAssertTrue(
      indicator.waitForExistence(timeout: 5),
      "In-flight indicator did not appear after parking the run.")

    // Tap it → return to the still-live run.
    indicator.tap()

    // Instant reconnect: the live header reappears and the "Loading scenario…"
    // reload state is never shown (adopt assigns the VM synchronously).
    XCTAssertTrue(
      header.waitForExistence(timeout: 5),
      "Returning to the run did not re-show the live SimulationView.")
    XCTAssertFalse(
      app.staticTexts["Loading scenario..."].exists,
      "Returning reloaded the scenario instead of adopting the live session.")
  }
}
