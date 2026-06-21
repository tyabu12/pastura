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
/// Subject to the UI-test flake classes in `.claude/rules/xcodebuild-cli.md`.
@MainActor
final class InFlightIndicatorReconnectUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
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

    // Reach SimulationView via the proven gallery-install → Run Simulation flow
    // (mirrors SimulationFocusModeTests).
    let browseTab = app.tabBars.buttons["Browse"]
    XCTAssertTrue(browseTab.waitForExistence(timeout: 5), "Browse tab missing.")
    browseTab.tap()

    let galleryCell = app.buttons["sharedScenarios.galleryCell.ui_test_canary"]
    XCTAssertTrue(galleryCell.waitForExistence(timeout: 5), "Canary gallery cell missing.")
    galleryCell.tap()

    let tryButton = app.buttons["galleryDetail.tryButton"]
    XCTAssertTrue(tryButton.waitForExistence(timeout: 5), "Try button missing.")
    tryButton.tap()

    let detailList = app.scrollViews["scenarioDetail.list"]
    XCTAssertTrue(detailList.waitForExistence(timeout: 10), "ScenarioDetailView did not appear.")
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
    XCTAssertTrue(header.waitForExistence(timeout: 10), "SimulationView did not appear.")

    // Leave with "keep running" (Setting on → silent park) via the interactive
    // edge-swipe (bypasses the dialog; coordinate drag required on iOS 17+).
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    start.press(forDuration: 0.15, thenDragTo: end)

    // The tab bar restores (left the sim) and the in-flight indicator appears.
    XCTAssertTrue(browseTab.waitForExistence(timeout: 5), "Tab bar did not restore after leaving.")
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
