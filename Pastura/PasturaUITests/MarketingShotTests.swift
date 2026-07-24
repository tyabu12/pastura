import XCTest

/// Zenn-article "inference screenshot" capture — renders the two curated
/// marketing transcripts (word_wolf, prisoners_dilemma) through the real
/// `ResultDetailView` timeline (the same `AgentOutputRow` renderer the live
/// simulation uses). `scripts/marketing-shots.sh` runs this pinned to the 6.9"
/// iPhone in **ja** and routes the attachments into
/// `docs/marketing/screenshots/` (gitignored). Source of the seeded text:
/// `docs/marketing/launch-transcripts.md` (verbatim, via `StubResultSeeder`).
///
/// Capture-only (asserts nothing against a reference), **local-only**,
/// CI-skipped via `-skip-testing PasturaUITests/MarketingShotTests` in
/// `ci.yml` — same class as `StoreScreenshotTests`. **ja / light only**: the
/// app uses a static `PasturaPalette` (no dark-mode adaptation), so light is
/// the only meaningful appearance.
@MainActor
final class MarketingShotTests: XCTestCase {
  private static let jaArgs = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    XCUIApplication().terminate()
  }

  /// Both fixtures in one method (like `StoreScreenshotTests`): each relaunches
  /// the app with its own seed arg. Two separate `@Test`-style methods flaked —
  /// the second method's cold relaunch could out-run `tapTab`'s 10s tab wait.
  func testCaptureMarketingShots() throws {
    captureFixture(seedArg: "--ui-test-seed-results-wordwolf", prefix: "wordwolf")
    captureFixture(seedArg: "--ui-test-seed-results-prisoners", prefix: "prisoners")
  }

  /// Launches with `seedArg`, opens the seeded result, and captures the
  /// timeline. Both fixtures are short enough that the whole story — statements,
  /// whisper + INNER VOICE, vote tallies, and the summary reveal — fits one 6.9"
  /// screen, so a single top-of-timeline shot is the complete deliverable.
  private func captureFixture(seedArg: String, prefix: String) {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test", seedArg] + Self.jaArgs
    app.launch()

    // ja-locked, so the label fallback is the ja one. See `tapTab` for why the
    // `rootTab.*` identifier alone is not enough. The 20s bound is NOT about
    // that bridging failure: the second fixture's capture reaches this after a
    // cold relaunch mid-test, which the default 10s has been observed to
    // out-run (see this class's doc-comment).
    tapTab(app, "rootTab.history", labelFallback: "観察履歴", timeout: 20)
    let row = app.buttons["results.row.ui_test_result_seed"]
    XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded result row did not appear.")
    row.tap()

    captureScreenshot(
      app, name: "\(prefix)-01-timeline", anchorId: "resultDetail.timeline", timeout: 10)
    app.terminate()
  }

}
