import XCTest

/// Verifies the Editor → Save → auto-pop → Home reload path (#110).
///
/// Flow under test:
///   1. Launch with `--ui-test` (seeds Home list) and `--ui-test-editor-seed-yaml`
///      (makes "New Scenario" open the editor pre-filled with the seed YAML).
///   2. Tap the "+" toolbar button to open the Add menu, then tap "New Scenario".
///   3. The editor opens pre-filled via `Route.editor(templateYAML:)`. Tap Save.
///   4. On successful save, the editor's `dismiss()` pops the root stack.
///   5. `HomeView.onChange(of: router.path.count)` fires and reloads user scenarios.
///   6. Assert the saved scenario's name appears on Home.
///
/// Why label-based assertion (not id-based):
///   `ScenarioEditorViewModel.loadFromTemplate` regenerates the scenario id to a
///   fresh UUID, so the `home.scenarioListCell.<id>` accessibility identifier is
///   unknowable from the test side. The scenario *name* ("UITest Editor Reload Seed")
///   is preserved verbatim by `loadFromTemplate`, so querying a `staticText` with
///   that label is reliable and unambiguous.
@MainActor
final class EditorReloadTests: XCTestCase {
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

  func testEditorSavePopsAndReloadsHome() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test", "--ui-test-editor-seed-yaml"]
    app.launch()

    // Wait for Home to finish initializing.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    // Sanity check: the editor-seed scenario name is NOT yet on Home (it hasn't
    // been saved through the editor yet — only the home-seed row is present).
    // Mirrors StubScenarioSeeder.editorSeedScenarioName
    let editorSeedName = "UITest Editor Reload Seed"
    XCTAssertFalse(
      app.staticTexts[editorSeedName].exists,
      "Editor seed scenario should not be on Home before editor save.")

    // Open the Add menu via the "+" toolbar button.
    let addButton = app.buttons["Add"]
    XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add toolbar button missing.")
    addButton.tap()

    // Tap "New Scenario" from the menu.
    // Use .firstMatch in case accessibility surfaces the NavigationLink label
    // as both a button and a label element simultaneously.
    let newScenarioItem = app.buttons["home.newScenarioButton"]
    var menuTapAttempts = 0
    while !newScenarioItem.exists && menuTapAttempts < 2 {
      // Menu may not have fully expanded — re-tap the Add button and retry.
      if menuTapAttempts > 0 {
        addButton.tap()
      }
      menuTapAttempts += 1
    }
    XCTAssertTrue(
      newScenarioItem.waitForExistence(timeout: 5),
      "New Scenario menu item missing — menu may not have opened.")
    newScenarioItem.tap()

    // Wait for the editor to appear. The editor Form renders as a collectionView
    // in XCUI. If the template YAML was pre-filled, the editor nav title matches
    // editorSeedScenarioName; use that as the primary appearance check.
    let editorNavBar = app.navigationBars[editorSeedName]
    let editorForm = app.collectionViews.firstMatch
    let editorAppeared =
      editorNavBar.waitForExistence(timeout: 10) || editorForm.waitForExistence(timeout: 5)
    XCTAssertTrue(editorAppeared, "Editor did not appear within 10s.")

    // Sanity check: Save button exists (implying the editor loaded correctly).
    let saveButton = app.buttons["editor.saveButton"]
    XCTAssertTrue(
      saveButton.waitForExistence(timeout: 5),
      "editor.saveButton missing — editor may not have loaded the seed YAML.")

    // Wait for the Save button to become enabled (guards against the brief
    // `.disabled(viewModel.isSaving)` window during any async validation).
    let enabledExpectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: saveButton)
    wait(for: [enabledExpectation], timeout: 10)
    saveButton.tap()

    // After a successful save, the editor calls `dismiss()`, which pops the root
    // NavigationStack. `HomeView.onChange(of: router.path.count)` then fires
    // and reloads user scenarios from the repository.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home nav bar did not reappear after editor save — dismiss/pop may have failed.")

    // Assert the saved scenario appears on Home by label. The id was regenerated
    // to a UUID by loadFromTemplate, so we cannot use the accessibility id.
    // Mirrors StubScenarioSeeder.editorSeedScenarioName
    let savedRow = app.staticTexts[editorSeedName]
    XCTAssertTrue(
      savedRow.waitForExistence(timeout: 10),
      "'\(editorSeedName)' did not appear on Home after editor save — "
        + "onChange(of: router.path.count) reload may not have fired.")
  }
}
