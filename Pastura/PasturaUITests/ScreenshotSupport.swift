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
  /// id from `RootTabView`), falling back to its localized `labelFallback`.
  ///
  /// **Why the fallback exists.** On some launches SwiftUI's structural `Tab`
  /// API never bridges the tab items' custom accessibility overlay into the
  /// XCUITest tree: the `rootTab.*` identifiers are absent *and* so are the
  /// `.accessibilityLabel`s `RootTabView.tabIcon` attaches (the icon `Image`
  /// exposes its raw SF Symbol name instead). The bar and its buttons exist and
  /// are hittable throughout — only the overlay is missing. Verified by
  /// exporting the "App UI hierarchy" attachment from a failed run's xcresult:
  /// `Button, label: 'History'` present, zero occurrences of `rootTab`.
  ///
  /// **Waiting does not fix it.** It is decided once per launch, not a race
  /// this call can outlast — observed here failing at a 10s bound, and the
  /// workaround this replaced had already widened its own identifier wait to
  /// 20s without success. That is why the two are ONE predicate rather than
  /// sequential waits: on a broken launch, waiting on the identifier first
  /// burns its whole timeout every time before the label gets a turn.
  ///
  /// `timeout` covers how long the tab bar itself may take to exist, which is
  /// a *separate* concern from the bridging failure above — a cold relaunch
  /// mid-test needs more of it than a first launch does.
  ///
  /// `labelFallback` must track the tab's `Localizable.xcstrings` value for the
  /// locale under test (e.g. `History` / `観察履歴`); a stale one fails loudly
  /// here rather than selecting a different tab.
  func tapTab(
    _ app: XCUIApplication, _ identifier: String, labelFallback: String,
    timeout: TimeInterval = 10
  ) {
    let tab = app.tabBars.buttons.matching(
      NSPredicate(format: "identifier == %@ OR label == %@", identifier, labelFallback)
    ).firstMatch
    XCTAssertTrue(
      tab.waitForExistence(timeout: timeout),
      "Tab '\(identifier)' (label '\(labelFallback)') did not appear within \(timeout)s.")
    tab.tap()
  }
}
