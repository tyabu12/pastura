import Testing

@testable import Pastura

/// Unit tests for `GalleryLanguageFilter` — the Browse tab's language-chip
/// filter projection. Covers the chip-options ordering, the option →
/// `selectedLanguage` mapping, and the device-default resolution.
/// Asserts logic properties only, never rendered output
/// (ADR-009 / `.claude/rules/view-testing.md`).
///
/// `@MainActor` on the suite matches the `SharedScenariosCategoryFilterTests`
/// precedent. It is not strictly load-bearing here: `GalleryLanguageFilter` is
/// declared `nonisolated`, so its auto-synthesized `Equatable` conformance
/// lookup is already nonisolated (swift-isolation Pattern 5 fires only for
/// default-MainActor types). Harmless belt-and-suspenders.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GalleryLanguageFilterTests {

  // MARK: - options(available:) ordering

  @Test func allChipIsFirst() {
    let opts = GalleryLanguageFilter.options(available: ["ja", "en"])
    #expect(opts.first == .all)
  }

  @Test func canonicalLanguagesInCanonicalOrder() {
    // ja before en in canonical order, both present.
    let opts = GalleryLanguageFilter.options(available: ["ja", "en"])
    #expect(opts == [.all, .language("ja"), .language("en")])
  }

  @Test func singleLanguageOnly() {
    // Only "en" in feed → no "ja" chip.
    let opts = GalleryLanguageFilter.options(available: ["en"])
    #expect(opts == [.all, .language("en")])
  }

  @Test func unknownLanguageAfterCanonical() {
    // "fr" is not canonical — it appears after "ja" alphabetically.
    let opts = GalleryLanguageFilter.options(available: ["fr", "ja"])
    #expect(opts == [.all, .language("ja"), .language("fr")])
  }

  @Test func multipleUnknownsAreSorted() {
    // Unknown languages sorted alphabetically after canonical entries.
    let opts = GalleryLanguageFilter.options(available: ["zh", "de", "ja"])
    #expect(opts == [.all, .language("ja"), .language("de"), .language("zh")])
  }

  @Test func emptyAvailableReturnsOnlyAll() {
    let opts = GalleryLanguageFilter.options(available: [])
    #expect(opts == [.all])
  }

  // MARK: - selectedLanguage mapping

  @Test func allMapsToNilSelectedLanguage() {
    #expect(GalleryLanguageFilter.all.selectedLanguage == nil)
  }

  @Test func languageCaseMapsToItsCode() {
    #expect(GalleryLanguageFilter.language("ja").selectedLanguage == "ja")
    #expect(GalleryLanguageFilter.language("en").selectedLanguage == "en")
  }

  // MARK: - resolveDefault

  @Test func deviceLanguagePresentReturnsDevice() {
    #expect(GalleryLanguageFilter.resolveDefault(device: "ja", available: ["ja", "en"]) == "ja")
  }

  @Test func deviceLanguageAbsentReturnsNil() {
    // Device is "fr" but feed has only ja/en → fall back to "all".
    #expect(GalleryLanguageFilter.resolveDefault(device: "fr", available: ["ja", "en"]) == nil)
  }

  @Test func emptyAvailableReturnsNil() {
    #expect(GalleryLanguageFilter.resolveDefault(device: "ja", available: []) == nil)
  }
}
