import Foundation
import Testing

@testable import Pastura

/// Catalog guard for the two strings that carry ADR-029 § Amendment
/// 2026-08-08's honesty requirements into the locale users actually read.
///
/// The amendment says a persona rendition's heading "must name itself an
/// excerpt", and that neither string may say "YAML" when none is shown. That is
/// pinned in `en` by `GalleryScenarioDetailFormatTests` — but a
/// `String(localized:)` resolve in a test reads the table the *runner's process
/// localization* selects (`en`), so those assertions say nothing about `ja`
/// (`.claude/rules/view-testing.md` § "Non-base-locale expectations"). Highlight
/// content is Japanese today, so `ja` is this feature's **primary** surface, and
/// `check_localization_coverage.py` validates presence and state but never value
/// content — a translator or a batch ja-fill dropping 「抜粋」 would pass every
/// other gate (`.claude/rules/i18n-catalog.md` § "Batch ja-fill", incident #382).
///
/// A change-detector against the catalog JSON, per `view-testing.md`
/// § "Change-detector tripwire for code-review-gated tokens". A failure here is
/// not automatically a bug — it means the ja wording moved, and whoever moved it
/// must confirm the replacement still carries the excerpt marker and still
/// avoids naming a medium it does not show.
@Suite(.timeLimit(.minutes(1)))
struct HookHeadingLocalizationTests {

  /// Same walk-up as `StoreCaptureTabLabelTests` — the catalog does not ship as
  /// `.xcstrings`, so it is read from source rather than the bundle.
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

  private static func japaneseValue(forKey key: String) throws -> String {
    let data = try Data(contentsOf: catalogURL())
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = try #require(json?["strings"] as? [String: Any])
    let entry = try #require(
      strings[key] as? [String: Any], "the key '\(key)' is gone from the catalog")
    // A *deleted* key fails the `#require` above, but a **reworded** English
    // literal does not: `xcstringstool sync` adds the new key and keeps the old
    // one as `extractionState: "stale"` with its `ja` value intact (this catalog
    // holds 26 such entries today). Without this the guard would keep passing
    // against a stale entry while the shipping heading lost its marker — the
    // exact vacuity it exists to prevent.
    #expect(
      entry["extractionState"] as? String != "stale",
      "'\(key)' is stale — the en literal moved; re-point this test at the new key")
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let ja = try #require(localizations["ja"] as? [String: Any], "'\(key)' has no ja")
    let unit = try #require(ja["stringUnit"] as? [String: Any])
    #expect(unit["state"] as? String == "translated")
    return try #require(unit["value"] as? String)
  }

  /// The excerpt marker is the whole invariant: two persona rows above a
  /// four-speaker run figure otherwise read as the scenario's complete cast.
  @Test func theJapanesePersonaHeadingNamesItselfAnExcerpt() throws {
    let value = try Self.japaneseValue(forKey: "Some of the personas behind these lines")
    #expect(value.contains("抜粋"))
  }

  /// The ja invitation must not promise a YAML edit under a rendition that
  /// shows no YAML — the defect a screenshot caught after the heading alone had
  /// been fixed. Its raw-rendition sibling still says YAML, correctly.
  @Test func theJapanesePersonaInvitationDoesNotPromiseYAML() throws {
    let personas = try Self.japaneseValue(
      forKey:
        "Once it is on your device you can rewrite these personas freely. Change the setup and see where your own run goes."
    )
    #expect(!personas.localizedCaseInsensitiveContains("yaml"))

    let raw = try Self.japaneseValue(
      forKey:
        "Once it is on your device you can rewrite this YAML freely. Change the setup and see where your own run goes."
    )
    #expect(raw.localizedCaseInsensitiveContains("yaml"))
  }
}
