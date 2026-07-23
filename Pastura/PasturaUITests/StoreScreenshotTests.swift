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
/// Shot 1 ("observation") is the Past-Results transcript replay: it renders the
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
  }

  private static let locales: [StoreLocale] = [
    StoreLocale(
      prefix: "en", language: "en", locale: "en_US",
      // Alice / Bob, two `speak_all` rounds with `inner_thought`.
      resultSeedArgument: "--ui-test-seed-results"),
    StoreLocale(
      prefix: "ja", language: "ja", locale: "ja_JP",
      // Word Wolf over `prisoners`: its statement → two votes → tally →
      // verdict fills the 6.9" frame, where the prisoners transcript leaves the
      // lower ~40% blank. The vote turns carry `reason`, which
      // `ScenarioConventions.thoughtField(for: .vote)` renders as the ▸ THINKING
      // section — so the shot-01 caption ("発言と、その裏にある心の声まで")
      // still holds even though this fixture has no `inner_thought` field.
      resultSeedArgument: "--ui-test-seed-results-wordwolf")
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

  /// Two launches per locale: launch A walks the seeded home/editor/results/
  /// transcript screens; launch B opens the fixed-data scoreboard. Tabs are
  /// switched by `rootTab.*` identifier (not the localized label) so the walk
  /// works under ja as well as en.
  private func captureStoreShots(for locale: StoreLocale) {
    let localeArgs = ["-AppleLanguages", "(\(locale.language))", "-AppleLocale", locale.locale]
    let prefix = locale.prefix

    let app = XCUIApplication()
    app.launchArguments =
      ["--ui-test", "--ui-test-seed-home-rich", locale.resultSeedArgument] + localeArgs
    app.launch()

    // 02 Home — the seeded row appears once HomeViewModel finishes loading.
    captureScreenshot(
      app, name: "\(prefix)-02-home",
      anchorId: "home.scenarioListCell.ui_test_home_seed", timeout: 10)

    // 03 Editor (new scenario), then back to Home.
    app.buttons["home.newScenarioButton"].tap()
    captureScreenshot(app, name: "\(prefix)-03-editor", anchorId: "editor.titleField")
    popBack(app)

    // 05 Past Results list — the History tab root (id-based switch is
    // locale-independent).
    tapTab(app, "rootTab.history")
    captureScreenshot(app, name: "\(prefix)-05-results", anchorId: "results.list")

    // 01 Observation transcript — speech + inner-voice bubbles (the seed
    // carries inner_thought; showAllThoughts defaults true).
    app.buttons["results.row.ui_test_result_seed"].tap()
    captureScreenshot(app, name: "\(prefix)-01-observation", anchorId: "resultDetail.timeline")

    // 04 Scoreboard — relaunch with the fixed-data scoreboard flag.
    app.terminate()
    app.launchArguments = ["--ui-test", "--ui-test-open-scoreboard"] + localeArgs
    app.launch()
    captureScreenshot(
      app, name: "\(prefix)-04-scoreboard", anchorId: "scoreboard.list", timeout: 10)
    app.terminate()
  }
}
