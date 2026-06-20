import Testing

@testable import Pastura

/// Tests for the Yams-free top-level `language:` scan used by the v8 migration
/// backfill and repository save-time backstop.
@Suite(.timeLimit(.minutes(1))) struct ScenarioLanguageScanTests {

  @Test func extractsTopLevelEnglish() {
    let yaml = """
      name: Word Wolf
      language: en
      rounds: 3
      """
    #expect(ScenarioLanguageScan.topLevelLanguage(in: yaml) == "en")
  }

  @Test func extractsTopLevelJapanese() {
    #expect(ScenarioLanguageScan.topLevelLanguage(in: "language: ja\nname: 人狼") == "ja")
  }

  @Test func stripsSurroundingQuotes() {
    #expect(ScenarioLanguageScan.topLevelLanguage(in: #"language: "en""#) == "en")
    #expect(ScenarioLanguageScan.topLevelLanguage(in: "language: 'ja'") == "ja")
  }

  /// The critical prefix-collision case: `simulation_language:` (ADR-010 D5) is
  /// a top-level sibling key. A substring match would mis-read it; the exact-key
  /// anchor must skip it and find the real `language:` below.
  @Test func ignoresSimulationLanguagePrefixCollision() {
    let yaml = """
      name: Cross-language run
      simulation_language: en
      language: ja
      """
    #expect(ScenarioLanguageScan.topLevelLanguage(in: yaml) == "ja")
  }

  /// `simulation_language` alone (no real `language:` key) must not satisfy
  /// the scan — the caller then applies its fallback.
  @Test func simulationLanguageAloneReturnsNil() {
    #expect(ScenarioLanguageScan.topLevelLanguage(in: "simulation_language: en") == nil)
  }

  /// Indented `language:` is a nested field (persona / extraData), not the
  /// scenario's top-level language.
  @Test func ignoresNestedLanguageKey() {
    let yaml = """
      name: Test
      personas:
        - name: Alice
          language: en
      """
    #expect(ScenarioLanguageScan.topLevelLanguage(in: yaml) == nil)
  }

  @Test func ignoresPluralLanguagesKey() {
    #expect(ScenarioLanguageScan.topLevelLanguage(in: "languages: [ja, en]") == nil)
  }

  @Test func returnsNilWhenAbsent() {
    #expect(ScenarioLanguageScan.topLevelLanguage(in: "name: Test\nrounds: 1") == nil)
  }
}
