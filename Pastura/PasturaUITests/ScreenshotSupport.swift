import XCTest

/// Shared screenshot helpers for the capture-only UI test classes
/// (`StoreScreenshotTests` store shots; `ScreenshotTourTests` keeps its own
/// private copy to stay undisturbed). Both are review/capture-only — they
/// assert nothing against a stored reference (ADR-009's snapshot-testing
/// rejection does not apply) and are CI-skipped.
@MainActor
extension XCTestCase {
  /// Waits for `anchorId` to appear (matched across all element types), then
  /// attaches a full-screen PNG named `name`.
  ///
  /// Capture names must be kebab-case with **no underscores** — the xcresult
  /// exporter appends `_<n>_<UUID>`, and the extraction scripts recover the
  /// name by splitting on `_`.
  func captureScreenshot(
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
  func popBack(_ app: XCUIApplication) {
    let back = app.buttons["pasturaBackButton"]
    XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button missing.")
    back.tap()
  }

  /// Switches to the tab whose bar button carries `identifier` (a `rootTab.*`
  /// id from `RootTabView`), waiting for it first so the accessibility tree
  /// has settled — a bare `.tap()` can hit XCUITest's intermittent
  /// "Automation type mismatch" on the structural `Tab` API.
  func tapTab(_ app: XCUIApplication, _ identifier: String) {
    let tab = app.tabBars.buttons[identifier]
    XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab '\(identifier)' did not appear.")
    tab.tap()
  }
}
