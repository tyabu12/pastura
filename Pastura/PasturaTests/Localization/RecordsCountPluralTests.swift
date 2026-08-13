import Foundation
import Testing

@testable import Pastura

/// Catalog-structure assertion for the **first plural** entry in
/// `Localizable.xcstrings` — the Past Results count line (`"%lld records"`,
/// UR-003). A change-detector test (`.claude/rules/view-testing.md`
/// § "Change-detector tripwire for code-review-gated tokens"), NOT a runtime
/// `String(localized:)` resolution:
/// the catalog compiles to a `.loctable` (no `.xcstrings` ships in the bundle),
/// and a runtime resolve against the test-runner bundle is both
/// bundle-ambiguous and tautological — and the SwiftUI `Text` plural path is
/// unreachable from a unit test without ViewInspector, which ADR-009 forbids.
///
/// This guards the plural variations from a future `xcstringstool sync`
/// flattening them back to a plain `stringUnit` (the catalog auto-syncs on every
/// `scripts/xcodebuild.sh build`): the `en` source must keep
/// `variations.plural.{one,other}` with both states `translated`. Japanese has
/// no plural category (CLDR `other`-only), so its plain `stringUnit` is asserted
/// to stay single-form — guarding against sync mirroring `en`'s variation shape
/// onto `ja`.
@Suite(.timeLimit(.minutes(1)))
struct RecordsCountPluralTests {

  /// Resolve the catalog relative to this test file. `#filePath` expands at
  /// compile time to the absolute source path; we walk up until we find the
  /// catalog under `Pastura/Pastura/Resources`.
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
    // Walk-up failed (catalog relocated?) — return an obviously-bogus path so
    // the downstream `Data(contentsOf:)` throws a self-explaining error rather
    // than an opaque read at "/".
    return URL(fileURLWithPath: "/Localizable.xcstrings-not-found-via-filePath-walkup")
  }

  /// The full `"%lld records"` catalog entry.
  private func entry() throws -> [String: Any] {
    let data = try Data(contentsOf: Self.catalogURL())
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = try #require(json?["strings"] as? [String: Any])
    return try #require(strings["%lld records"] as? [String: Any])
  }

  /// The `"%lld records"` entry's `localizations` object.
  private func localizations() throws -> [String: Any] {
    try #require(try entry()["localizations"] as? [String: Any])
  }

  /// Extract `(value, state)` from a `stringUnit` object.
  private func stringUnit(_ container: [String: Any]?) throws -> (String, String) {
    let unit = try #require(container?["stringUnit"] as? [String: Any])
    let value = try #require(unit["value"] as? String)
    let state = try #require(unit["state"] as? String)
    return (value, state)
  }

  @Test func englishHasPluralVariations() throws {
    let en = try #require(try localizations()["en"] as? [String: Any])
    let plural = try #require(
      (en["variations"] as? [String: Any])?["plural"] as? [String: Any])

    let (oneValue, oneState) = try stringUnit(plural["one"] as? [String: Any])
    #expect(oneValue == "%lld record")
    #expect(oneState == "translated")

    let (otherValue, otherState) = try stringUnit(plural["other"] as? [String: Any])
    #expect(otherValue == "%lld records")
    #expect(otherState == "translated")
  }

  @Test func japaneseStaysSingleForm() throws {
    let ja = try #require(try localizations()["ja"] as? [String: Any])
    // No plural bucket for ja — Japanese CLDR has only `other`, so the single
    // form is correct. Guards against sync mirroring en's variations onto ja.
    #expect(ja["variations"] == nil)

    let (value, state) = try stringUnit(ja)
    #expect(value == "%lld 回の記録")
    #expect(state == "translated")
  }

  @Test func englishPluralFiresAtRuntime() throws {
    // Behavioral counterpart to the structure assertions: resolve the key
    // against the COMPILED catalog, naming the app bundle explicitly (the
    // target is app-hosted, so `Bundle.main` is the same bundle), with a
    // pinned `en` locale. The pin fixes the plural RULE, not the table — the
    // table follows the runner's process localization, which is `en` on every
    // simulator we run, so pinning a non-base locale here would silently keep
    // reading `en` (`.claude/rules/view-testing.md` § "Non-base-locale
    // expectations"). That precondition is REQUIRED below rather than assumed:
    // `#require` halts the test, so a ja-configured runner reports the wrong
    // runner locale and never emits the value mismatches that would read as a
    // catalog regression. This is the actual UR-003 regression
    // — n=1 rendering "1 records". Not a tautology (asserts hardcoded literals)
    // and not ViewInspector (pure Foundation resolution, ADR-009-compatible).
    // The Int interpolation here is the same plural mechanism the
    // `Text("\(count)…")` callsite uses; `String(localized: "…\(x)…")` is fine
    // in test code (the `form_a_localized_interpolation` SwiftLint rule scopes
    // to app source).
    let bundle = Bundle(for: DatabaseManager.self)
    try #require(bundle.preferredLocalizations.first == "en")
    let en = Locale(identifier: "en")
    #expect(String(localized: "\(1) records", bundle: bundle, locale: en) == "1 record")
    #expect(String(localized: "\(2) records", bundle: bundle, locale: en) == "2 records")
    // n=0 falls to the `other` bucket in en CLDR (not reachable at the callsite
    // — empty-state guard — but pinned here to document the CLDR behavior).
    #expect(String(localized: "\(0) records", bundle: bundle, locale: en) == "0 records")
  }

  @Test func keyIsManuallyManaged() throws {
    // `extractionState: "manual"` is load-bearing. The callsite is
    // `Text("\(count) records")` — the COMPILER extracts key "%lld records"
    // (it knows `count: Int` → `%lld`), but the wrapper's source-based
    // `xcstringstool extract` (no type info) cannot resolve the interpolation,
    // so its sync would mark the key `stale` on every build. `manual` opts the
    // key out of auto-sync staling/pruning. Removing it ⇒ perpetual stale
    // churn. See .claude/rules/i18n-ui.md § "Plurals — the sanctioned exception to Form B".
    #expect(try entry()["extractionState"] as? String == "manual")
  }
}
