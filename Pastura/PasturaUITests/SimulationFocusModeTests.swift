import XCTest

/// Focus mode (#646): while a simulation is on top of a tab's stack, the bottom
/// tab bar is hidden (`.toolbar(.hidden, for: .tabBar)` on `SimulationView`), so
/// tab-switching mid-run is structurally impossible — the bug #646 set out to
/// fix (tab switch → view teardown → reset) can no longer be triggered.
///
/// This UI test guards the **simulator-observable** mechanism only: the bar
/// disappears on push and restores on pop. The iOS-26 restore-on-pop *visual*
/// (Liquid Glass flicker / half-render / stuck-hidden) is NOT validated here —
/// per `.claude/rules/swiftui-traps.md` "simulator-only QA is not load-bearing",
/// that is the device-QA gate's job (#646 C-1). `.tabBar` is a separate toolbar
/// surface from the navigationBar hide matrix and does not interact with the
/// swipe-back gesture.
///
/// Subject to the UI-test flake classes in `.claude/rules/xcodebuild-cli.md`
/// (within-process clone cascade / app-launch timeout / runner-init).
@MainActor
final class SimulationFocusModeTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    XCUIApplication().terminate()
  }

  func testTabBarHiddenDuringSimulationAndRestoredOnPop() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test"]
    app.launch()

    // Wait for Home to finish initializing.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    // Reach SimulationView via the proven gallery-install → Run Simulation flow
    // (mirrors NavigationRegressionTests — the path known to start a sim under
    // the `--ui-test` harness).
    let browseTab = app.tabBars.buttons["Browse"]
    XCTAssertTrue(browseTab.waitForExistence(timeout: 5), "Browse tab missing.")
    browseTab.tap()

    let galleryCell = app.buttons["sharedScenarios.galleryCell.ui_test_canary"]
    XCTAssertTrue(
      galleryCell.waitForExistence(timeout: 5),
      "Canary gallery cell missing — StubGalleryService fixture may be wrong.")
    galleryCell.tap()

    let tryButton = app.buttons["galleryDetail.tryButton"]
    XCTAssertTrue(
      tryButton.waitForExistence(timeout: 5), "Try button missing on gallery detail.")
    tryButton.tap()

    let detailList = app.scrollViews["scenarioDetail.list"]
    XCTAssertTrue(
      detailList.waitForExistence(timeout: 10),
      "ScenarioDetailView did not appear after install.")
    let runSimulation = app.buttons["scenarioDetail.runSimulationButton"]
    var scrollAttempts = 0
    while !runSimulation.exists && scrollAttempts < 6 {
      detailList.swipeUp()
      scrollAttempts += 1
    }
    XCTAssertTrue(
      runSimulation.waitForExistence(timeout: 5),
      "Run Simulation button did not appear after scrolling.")
    let enabledExpectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: runSimulation)
    wait(for: [enabledExpectation], timeout: 10)
    runSimulation.tap()

    // SimulationView is now on top. Anchor on the always-rendered meta-row inset
    // (present from first frame, before any inference) — same anchor as
    // NavigationRegressionTests.
    XCTAssertTrue(
      app.descendants(matching: .any)["simulation.header.meta"].waitForExistence(timeout: 10),
      "SimulationView did not appear.")

    // Focus mode: the tab bar must disappear while the sim is on top. The hide
    // is unconditional on SimulationView, so it holds regardless of whether the
    // (mock) run has already completed.
    let tabBarGone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: browseTab)
    wait(for: [tabBarGone], timeout: 5)

    // Pop via the interactive edge-swipe — it bypasses the confirm-on-leave
    // dialog by design (see SimulationView.PendingLeave), so this is robust to
    // the mock run's completion timing. Coordinate-based drag is required;
    // swipeRight() does not trigger interactivePopGestureRecognizer on iOS 17+
    // (mirrors BackGestureTests).
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    start.press(forDuration: 0.15, thenDragTo: end)

    // The tab bar must restore once the simulation is popped.
    XCTAssertTrue(
      browseTab.waitForExistence(timeout: 5),
      "Tab bar did not restore after popping the simulation — focus-mode tab-bar"
        + " hide did not reverse on pop.")
  }
}
