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

    // Switch to the Browse tab (Shared Scenarios is its root since
    // ADR-016 D4 — no longer a Home push).
    let browseTab = app.tabBars.buttons["Browse"]
    XCTAssertTrue(
      browseTab.waitForExistence(timeout: 5), "Browse tab missing.")
    browseTab.tap()

    XCTAssertTrue(
      app.navigationBars["Browse Shared Scenarios"].waitForExistence(timeout: 5),
      "Browse Shared Scenarios did not appear.")

    // Shared Scenarios → Gallery scenario detail (push within the Browse tab).
    let galleryCell = app.buttons["sharedScenarios.galleryCell.ui_test_canary"]
    XCTAssertTrue(
      galleryCell.waitForExistence(timeout: 5),
      "Canary gallery cell missing — StubGalleryService fixture may be wrong.")
    galleryCell.tap()

    // Gallery detail → tap Try, wait for install.
    let tryButton = app.buttons["galleryDetail.tryButton"]
    XCTAssertTrue(
      tryButton.waitForExistence(timeout: 5), "Try button missing on gallery detail.")
    tryButton.tap()

    // After install, `pushIfOnTop` advances to the installed ScenarioDetailView
    // (now a ScrollView of PasturaCards). Scroll so the actions card (below the
    // overview / context / personas / phases cards) enters the accessibility
    // tree before asserting on the Run Simulation row.
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
    // Waits for .disabled(!canRun) to flip to enabled.
    let enabledExpectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: runSimulation)
    wait(for: [enabledExpectation], timeout: 10)
    runSimulation.tap()

    // Canary assertion: SimulationView's meta-row inset is the always-
    // rendered surface after the route transition, BEFORE any LLM
    // inference (its `safeAreaInset(.top)` falls through to a 1pt spacer
    // when `hasMetaRow == false`, so the identifier exists from first
    // frame — see `SimulationView.headerMetaInset`). The split-header
    // refactor in #344 moved the title row into `ToolbarItem(.principal)`
    // (UIKit-bridged tree placement), so we anchor on the meta inset
    // instead of the previously-unified `simulation.header`. Using
    // `descendants(matching:)` keeps the query immune to UIKit/SwiftUI
    // tree-placement quirks. If the PR #93 regression returns, this
    // times out because the stack either stays on ScenarioDetailView or
    // re-pushes it.
    let simulationHeader = app.descendants(matching: .any)["simulation.header.meta"]
    XCTAssertTrue(
      simulationHeader.waitForExistence(timeout: 10),
      "SimulationView meta-row inset did not appear — navigation regression suspected.")
  }
}
