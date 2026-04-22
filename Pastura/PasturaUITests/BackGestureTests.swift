import XCTest

/// Verifies that the interactive back gesture (edge-pan from left) pops exactly
/// one level off the root NavigationStack — Home → ScenarioDetail → back to Home.
/// We use a coordinate-based press-drag rather than `swipeRight()` because iOS 17+
/// simulators do not reliably trigger the interactive-pop gesture with the latter.
/// Regression: any accidental `navigationDestination(item:|isPresented:)` inside a
/// pushed view can intercept the gesture and leave an orphaned entry on the stack.
@MainActor
final class BackGestureTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    // Explicitly terminate so the simulator releases the app process before
    // the next test class launches a fresh one. Helps avoid "Failed to get
    // background assertion" infrastructure errors on resource-tight CI
    // simulators.
    XCUIApplication().terminate()
  }

  func testBackGestureFromScenarioDetailReturnsToHome() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test"]
    app.launch()

    // Wait for Home to finish initializing.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    // Tap the seeded scenario cell to push ScenarioDetailView.
    let scenarioCell = app.buttons["home.scenarioListCell.ui_test_home_seed"]
    XCTAssertTrue(
      scenarioCell.waitForExistence(timeout: 5),
      "Seed scenario cell missing — StubScenarioSeeder fixture may be wrong.")
    scenarioCell.tap()

    // ScenarioDetailView uses List (renders as a collectionView in XCUI).
    let detailList = app.collectionViews.firstMatch
    XCTAssertTrue(
      detailList.waitForExistence(timeout: 10),
      "ScenarioDetailView did not appear after tapping the scenario cell.")

    // Perform the interactive-pop edge-pan from the left edge.
    // Coordinate-based drag is required — swipeRight() does not trigger
    // UINavigationController's interactivePopGestureRecognizer on iOS 17+.
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    start.press(forDuration: 0.15, thenDragTo: end)

    // Home nav bar must return — confirming we popped exactly one level.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 5),
      "Home nav bar did not reappear after back gesture — interactive-pop regression suspected.")
  }
}
