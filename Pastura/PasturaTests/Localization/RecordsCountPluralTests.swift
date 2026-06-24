import Foundation
import Testing

/// Catalog-structure assertion for the **first plural** entry in
/// `Localizable.xcstrings` — the Past Results count line (`"%lld records"`,
/// UR-003). A change-detector test (`.claude/rules/view-testing.md`
/// § "Change-detector tripwire"), NOT a runtime `String(localized:)` resolution:
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
    return url
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

  @Test func keyIsManuallyManaged() throws {
    // `extractionState: "manual"` is load-bearing. The callsite is
    // `Text("\(count) records")` — the COMPILER extracts key "%lld records"
    // (it knows `count: Int` → `%lld`), but the wrapper's source-based
    // `xcstringstool extract` (no type info) cannot resolve the interpolation,
    // so its sync would mark the key `stale` on every build. `manual` opts the
    // key out of auto-sync staling/pruning. Removing it ⇒ perpetual stale
    // churn. See .claude/rules/i18n.md § "Plurals".
    #expect(try entry()["extractionState"] as? String == "manual")
  }
}
