import XCTest

/// Canary for the PR #93 regression: tapping **Run Simulation** from a
/// gallery-installed `ScenarioDetailView` must advance to `SimulationView`,
/// not re-push the scenario detail. The bug originated from mixing
/// `navigationDestination(item:)` with the root `Route` registry.
///
/// This flow exercises the full integration boundary — the `AppRouter` path,
/// `Route` dispatch, and the post-install `pushIfOnTop` guard — so any
/// future regression of the same class fails here rather than in manual QA.
@MainActor
final class NavigationRegressionTests: XCTestCase {
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

  func testGalleryInstallThenRunSimulationReachesSimulationView() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test"]
    app.launch()

    // Wait for Home to finish initializing.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    // Home → Share Board.
    let shareBoardCell = app.buttons["home.shareBoardButton"]
    XCTAssertTrue(
      shareBoardCell.waitForExistence(timeout: 5), "Share Board entry missing.")
    shareBoardCell.tap()

    XCTAssertTrue(
      app.navigationBars["Share Board"].waitForExistence(timeout: 5),
      "Share Board did not appear.")

    // Share Board → Gallery scenario detail.
    let galleryCell = app.buttons["shareBoard.galleryCell.ui_test_canary"]
    XCTAssertTrue(
      galleryCell.waitForExistence(timeout: 5),
      "Canary gallery cell missing — StubGalleryService fixture may be wrong.")
    galleryCell.tap()

    // Gallery detail → tap Try, wait for install.
    let tryButton = app.buttons["galleryDetail.tryButton"]
    XCTAssertTrue(
      tryButton.waitForExistence(timeout: 5), "Try button missing on gallery detail.")
    tryButton.tap()

    // After install, `pushIfOnTop` advances to the installed ScenarioDetailView.
    // Scroll the List so the actionsSection (below the fold after overview,
    // context, personas, phases, validation) enters the accessibility tree —
    // SwiftUI Lists lazy-render offscreen rows.
    let detailList = app.collectionViews.firstMatch
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
    // Waits for .disabled(!canRun) to flip to enabled.
    let enabledExpectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: runSimulation)
    wait(for: [enabledExpectation], timeout: 10)
    runSimulation.tap()

    // Canary assertion: SimulationView header is the first element that
    // renders after the route transition, BEFORE any LLM inference. If the
    // regression returns, this times out because the stack either stays on
    // ScenarioDetailView or re-pushes it.
    let simulationHeader = app.otherElements["simulation.header"]
    XCTAssertTrue(
      simulationHeader.waitForExistence(timeout: 10),
      "SimulationView header did not appear — navigation regression suspected.")
  }
}
