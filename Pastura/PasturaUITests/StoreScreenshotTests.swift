import XCTest

/// App Store screenshot capture — produces the store shots in **en and ja** at
/// 6.9" (1320×2868). `scripts/store-shots.sh` runs this class pinned to
/// iPhone 17 Pro Max and routes the attachments into
/// `docs/store/screenshots/{en,ja}/` (gitignored). See
/// `docs/store/screenshot-plan.md`.
///
/// Capture-only (asserts nothing against a reference), **local-only**,
/// CI-skipped via `-skip-testing:PasturaUITests/StoreScreenshotTests` in
/// `ci.yml`.
///
/// #1612's set: 01 observation transcript (History tab replay), 02 gallery
/// scenario detail with highlight (Browse tab → the seeded `iiwake_battle_v1`
/// cell), 03 Browse gallery list (anchored on that same cell), 04 the visual
/// editor, 05 the fixed-data scoreboard. The old Home-list and Past-Results-
/// list shots are dropped — `StubGalleryService.uiTestStoreGallery()`
/// (`StubGalleryService+StoreGallery.swift`) now supplies the gallery fixture
/// shots 02/03 read.
///
/// Shot 01 ("observation") is the Past-Results transcript replay: it renders the
/// same `AgentOutputRow` speech + inner-voice bubbles the live simulation uses.
/// The live `SimulationView` is not reachable under `--ui-test`
/// (`MockLLMService(responses: [])` throws on any generate), so the
/// deterministic replay is captured instead — see `StubResultSeeder`.
///
/// **The transcript fixture is per-locale.** Both locales used to seed the
/// English Alice/Bob fixture, so the ja shot rendered Japanese UI chrome around
/// an English conversation. ja now seeds the Word Wolf marketing transcript (a
/// verbatim Japanese run). Home / Past-Results row copy is localized separately,
/// inside `StubScenarioSeeder` — the launch argument only picks the transcript.
@MainActor
final class StoreScreenshotTests: XCTestCase {
  /// One captured locale (a struct, not a tuple — SwiftLint `large_tuple` caps
  /// tuples at 2 members). `store-shots.sh` routes by `prefix`.
  private struct StoreLocale {
    let prefix: String
    let language: String  // `-AppleLanguages` code
    let locale: String  // `-AppleLocale`
    /// Which `StubResultSeeder.MarketingFixture` to seed for shot 01.
    let resultSeedArgument: String
    /// History tab's localized label, used when the `rootTab.*` identifier
    /// fails to bridge — see `tapTab`. **Keep in sync with the `History` key in
    /// `Localizable.xcstrings`.**
    let historyTabLabel: String
    /// Browse tab's localized label, same fallback role as `historyTabLabel`.
    /// **Keep in sync with the `Browse` key in `Localizable.xcstrings`.**
    let browseTabLabel: String
    /// The seeded `iiwake_battle_v1*` gallery entry's id for this locale —
    /// `StubGalleryService.uiTestStoreGallery()` sorts it first within its
    /// language filter. Drives the `sharedScenarios.galleryCell.<id>`
    /// identifier for shots 02/03.
    let galleryCellId: String
  }

  private static let locales: [StoreLocale] = [
    StoreLocale(
      prefix: "en", language: "en", locale: "en_US",
      // Alice / Bob, two `speak_all` rounds with `inner_thought`.
      resultSeedArgument: "--ui-test-seed-results",
      historyTabLabel: "History",
      browseTabLabel: "Browse",
      galleryCellId: "iiwake_battle_v1_en"),
    StoreLocale(
      prefix: "ja", language: "ja", locale: "ja_JP",
      // Word Wolf over `prisoners`: its statement → two votes → tally →
      // verdict fills the 6.9" frame, where the prisoners transcript leaves the
      // lower ~40% blank. The vote turns carry `reason`, which
      // `ScenarioConventions.thoughtField(for: .vote)` renders as the ▸ THINKING
      // section — so the shot-01 caption ("発言と、その裏にある心の声まで")
      // still holds even though this fixture has no `inner_thought` field.
      resultSeedArgument: "--ui-test-seed-results-wordwolf",
      historyTabLabel: "観察履歴",
      browseTabLabel: "さがす",
      galleryCellId: "iiwake_battle_v1")
  ]

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    XCUIApplication().terminate()
  }

  func testCaptureStoreShots() throws {
    for locale in Self.locales {
      captureStoreShots(for: locale)
    }
  }

  /// Two launches per locale: launch A walks the seeded editor/gallery/
  /// results/transcript screens; launch B opens the fixed-data scoreboard.
  /// Tabs are switched via `tapTab`, which matches the `rootTab.*` identifier
  /// OR the locale's label, so the walk works under ja as well as en even on a
  /// launch where the identifier never bridges.
  private func captureStoreShots(for locale: StoreLocale) {
    let localeArgs = ["-AppleLanguages", "(\(locale.language))", "-AppleLocale", locale.locale]
    let prefix = locale.prefix

    let app = XCUIApplication()
    app.launchArguments =
      [
        "--ui-test", "--ui-test-seed-home-rich", "--ui-test-seed-store-gallery",
        locale.resultSeedArgument
      ] + localeArgs
    app.launch()

    // 04 Editor (new scenario), then back to Home.
    app.buttons["home.newScenarioButton"].tap()
    captureScreenshot(app, name: "\(prefix)-04-editor", anchorId: "editor.titleField")
    popBack(app)

    // Browse tab root — the tab bar identifier OR localized label, so the
    // switch survives a launch that drops the identifier.
    tapTab(app, "rootTab.search", labelFallback: locale.browseTabLabel)

    // 03 Browse gallery list, anchored on the locale's own `iiwake_battle_v1*`
    // cell. That cell also carries the highlight, so anchoring on it — rather
    // than the tab's own container — means the capture waits for the
    // language-filter chip (seeded on first index load) to settle too.
    let galleryCellId = "sharedScenarios.galleryCell.\(locale.galleryCellId)"
    captureScreenshot(app, name: "\(prefix)-03-browse", anchorId: galleryCellId, timeout: 10)

    // 02 Gallery scenario detail with highlight. The highlight section sits
    // below the "What happens" phase list, so once it has rendered, scroll it
    // into view — measured on the first 1.3 capture, only its first row peeked
    // out from under the tab bar without a scroll. A fixed-distance, slow drag
    // with a hold at the end (not `swipeUp()`, whose inertia carried the
    // section's header under the nav bar on the second capture) parks the
    // section heading in the upper part of the frame in both locales.
    app.buttons[galleryCellId].tap()
    let runFigure = app.descendants(matching: .any)["galleryDetail.highlightRunFigure"]
    XCTAssertTrue(
      runFigure.waitForExistence(timeout: 10),
      "Highlight run figure never rendered for \(galleryCellId).")
    let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
    let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37))
    dragStart.press(
      forDuration: 0.1, thenDragTo: dragEnd, withVelocity: .slow, thenHoldForDuration: 0.3)
    captureScreenshot(
      app, name: "\(prefix)-02-highlight", anchorId: "galleryDetail.highlightRunFigure",
      timeout: 10)
    popBack(app)

    // History tab root (identifier OR localized label).
    tapTab(app, "rootTab.history", labelFallback: locale.historyTabLabel)

    // 01 Observation transcript — speech + inner-voice bubbles. Which field
    // carries the thought is per-phase (`ScenarioConventions.thoughtField(for:)`):
    // `inner_thought` for en's speak_all turns, `reason` for ja's vote turns.
    // `showAllThoughts` defaults true. The dropped Past-Results-list shot used
    // to be the wait that let the History store load finish before this tap;
    // wait on the row explicitly now.
    let resultRow = app.buttons["results.row.ui_test_result_seed"]
    XCTAssertTrue(resultRow.waitForExistence(timeout: 10), "Seeded result row never appeared.")
    resultRow.tap()
    captureScreenshot(app, name: "\(prefix)-01-observation", anchorId: "resultDetail.timeline")

    // 05 Scoreboard — relaunch with the fixed-data scoreboard flag.
    app.terminate()
    app.launchArguments = ["--ui-test", "--ui-test-open-scoreboard"] + localeArgs
    app.launch()
    captureScreenshot(
      app, name: "\(prefix)-05-scoreboard", anchorId: "scoreboard.list", timeout: 10)
    app.terminate()
  }
}
