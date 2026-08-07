import Foundation
import Testing

@testable import Pastura

/// Catalog-structure guard for the tab label the App Store capture depends on.
///
/// `StoreScreenshotTests` and `MarketingShotTests` tap the History tab by its
/// **localized label** when SwiftUI fails to bridge the `rootTab.*` identifier
/// (see `ScreenshotSupport.tapTab`). Those classes are local-only and
/// CI-skipped, so a translator changing `History`'s ja value would otherwise
/// surface for the first time as a failed re-capture during a release — the one
/// moment with no slack for it. This fails in CI instead.
///
/// A change-detector against the catalog JSON (`.claude/rules/view-testing.md`
/// § "Change-detector tripwire for code-review-gated tokens"), **not** a
/// runtime `String(localized:)` resolution. A pinned-`ja` resolve was tried
/// first and returned `"History"`: `locale:` selects the plural/format rule,
/// not the `.lproj` table, so it read the `en` table — where this key has no
/// entry of its own, hence the key came back. Same reason
/// `RecordsCountPluralTests` pins only `en`. See view-testing.md
/// § "Non-base-locale expectations".
///
/// A failure here is not necessarily a bug: it means the ja label moved, and
/// whoever moved it must also update the `historyTabLabel` literals in
/// `StoreScreenshotTests.locales` and `MarketingShotTests`.
@Suite(.timeLimit(.minutes(1)))
struct StoreCaptureTabLabelTests {

  /// Resolve the catalog relative to this test file — same walk-up as
  /// `RecordsCountPluralTests` (the catalog does not ship as `.xcstrings`).
  private static func catalogURL() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.path != "/" {
      url.deleteLastPathComponent()
      let candidate = url.appendingPathComponent(
        "Pastura/Pastura/Resources/Localizable.xcstrings")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    return URL(fileURLWithPath: "/Localizable.xcstrings-not-found-via-filePath-walkup")
  }

  @Test func testHistoryTabJapaneseLabelMatchesTheCaptureFallback() throws {
    let data = try Data(contentsOf: Self.catalogURL())
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = try #require(json?["strings"] as? [String: Any])
    let entry = try #require(
      strings["History"] as? [String: Any],
      "the `History` key is gone from the catalog — the tab label moved")
    // Same stale-entry vacuity `HookHeadingLocalizationTests` guards: a
    // reworded en literal leaves this key behind as `extractionState: "stale"`
    // with its ja value intact, so the assertion below would keep passing
    // against an entry the app no longer resolves.
    #expect(
      entry["extractionState"] as? String != "stale",
      "'History' is stale — the en literal moved; re-point this test at the new key")
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let ja = try #require(localizations["ja"] as? [String: Any])
    let unit = try #require(ja["stringUnit"] as? [String: Any])

    // Keep in sync with `MarketingShotTests`' ja literal and the `ja` row of
    // `StoreScreenshotTests.locales`.
    #expect(unit["value"] as? String == "観察履歴")
    #expect(unit["state"] as? String == "translated")
  }
}
