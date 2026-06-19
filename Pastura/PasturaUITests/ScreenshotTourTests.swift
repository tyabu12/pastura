import XCTest

/// Review-only screenshot tour — walks the major screens under `--ui-test`
/// and attaches a full-screen PNG per stop. `scripts/ui-tour.sh` runs this
/// class and extracts the attachments into `docs/design/screenshots/` for
/// design review by humans and agents.
///
/// NOT a snapshot-assertion test: it compares nothing against a stored
/// reference and gates nothing (ADR-009's rejection of snapshot testing
/// does not apply — see the ADR's review-only capture note). Excluded from
/// CI via `-skip-testing:PasturaUITests/ScreenshotTourTests` in `ci.yml`.
///
/// Adding a screen: navigate to it, then call
/// `capture(app, name: "NN-screen-name", anchorId: "<identifier>")` with an
/// identifier that only exists once the screen's content has loaded. The
/// numeric prefix keeps extracted files in tour order; the anchor wait keeps
/// captures deterministic (never use fixed sleeps). Names must be
/// NN-kebab-case with NO underscores — the exporter appends `_<n>_<UUID>`
/// and `ui-tour.sh` recovers the name by splitting on `_`.
@MainActor
final class ScreenshotTourTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    // Explicitly terminate so the simulator releases the app process before
    // the next test class launches a fresh one (same rationale as
    // NavigationRegressionTests).
    XCUIApplication().terminate()
  }

  func testCaptureScreenshotTour() throws {
    let app = XCUIApplication()
    // --ui-test-seed-home-rich seeds presets + a gallery-sourced "shared" row
    // so the Home capture exercises the multi-row grouped card (d3, #684).
    // --ui-test-seed-results adds a completed simulation fixture so the Past
    // Results stops render content instead of the empty state. No paused run
    // here, so the resume card is absent (the 01b relaunch below adds it).
    app.launchArguments = ["--ui-test", "--ui-test-seed-home-rich", "--ui-test-seed-results"]
    app.launch()

    // Home — the seeded row only appears once HomeViewModel finishes loading.
    capture(
      app, name: "01-home",
      anchorId: "home.scenarioListCell.ui_test_home_seed", timeout: 10)

    // Scenario detail (seeded scenario) — the List carries its identifier
    // only after the scenario content has resolved.
    app.buttons["home.scenarioListCell.ui_test_home_seed"].tap()
    capture(app, name: "02-scenario-detail", anchorId: "scenarioDetail.list")
    goBack(app)

    // Editor (new scenario).
    app.buttons["home.newScenarioButton"].tap()
    capture(app, name: "03-editor", anchorId: "editor.titleField")
    goBack(app)

    // Shared Scenarios gallery — now the "Browse" tab root (ADR-016 D4),
    // reached via the tab bar rather than a Home push.
    app.tabBars.buttons["Browse"].tap()
    capture(
      app, name: "04-shared-scenarios",
      anchorId: "sharedScenarios.galleryCell.ui_test_canary")

    // Gallery scenario detail (push within the Browse tab stack).
    app.buttons["sharedScenarios.galleryCell.ui_test_canary"].tap()
    capture(app, name: "05-gallery-detail", anchorId: "galleryDetail.tryButton")
    // Single goBack pops the gallery detail back to the Browse tab root,
    // which has no back chevron.
    goBack(app)

    // Settings — a dedicated tab (ADR-016 D4), reached via the tab bar
    // rather than a Home push. Switching tabs doesn't push, so there is no
    // back chevron here.
    app.tabBars.buttons["Settings"].tap()
    capture(app, name: "06-settings", anchorId: "settings.licensesLink")

    // Past Results — now the History tab root (ADR-016 D4), reached via the
    // tab bar (seeded fixture — see StubResultSeeder). As a tab root it has
    // no parent to pop to, so confirm the back chevron is absent before
    // descending into the detail.
    app.tabBars.buttons["History"].tap()
    capture(app, name: "07-results", anchorId: "results.list")
    XCTAssertFalse(
      app.buttons["pasturaBackButton"].exists,
      "History tab root must not show a back chevron.")

    // Result detail timeline (a push onto the History tab stack).
    app.buttons["results.row.ui_test_result_seed"].tap()
    capture(app, name: "08-result-detail", anchorId: "resultDetail.timeline")
    // Single goBack pops the result detail back to the History tab root,
    // which has no back chevron.
    goBack(app)

    // Home (resume variant) — relaunch with the paused fixture so the Home
    // resume card renders (d3-with). Done as a relaunch at the end to leave the
    // linear walk above undisturbed. The name MUST be a strict `NN-` prefix
    // (two digits + dash): ui-tour.sh's exporter filter is `^[0-9]{2}-`, so a
    // `01b-` form is silently dropped — hence `09-` rather than `01b-`.
    // --ui-test-seed-paused implies the rich seed (PasturaApp pairs them), so
    // presets + the shared row are present too. Anchor on the resume button so
    // the capture waits for the card, not just the list.
    app.terminate()
    app.launchArguments = ["--ui-test", "--ui-test-seed-paused"]
    app.launch()
    capture(app, name: "09-home-resume", anchorId: "home.resumeButton", timeout: 10)
  }

  // MARK: - Helpers

  /// Waits for the element identified by `anchorId` (matched across all
  /// element types — buttons, text fields, collection views), then attaches
  /// a full-screen PNG named `name`.
  private func capture(
    _ app: XCUIApplication, name: String, anchorId: String,
    timeout: TimeInterval = 5
  ) {
    let anchor = app.descendants(matching: .any)[anchorId]
    XCTAssertTrue(
      anchor.waitForExistence(timeout: timeout),
      "Anchor '\(anchorId)' for screenshot '\(name)' did not appear within \(timeout)s.")
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Pops the current root-stack screen via `PasturaBackButton`.
  private func goBack(_ app: XCUIApplication) {
    let back = app.buttons["pasturaBackButton"]
    XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button missing.")
    back.tap()
  }
}
