import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScenarioYAMLLanguageTests {
  @Test func parseReturnsLanguageFieldFromWellFormedYAML() {
    let yaml = "id: word_wolf\nlanguage: en\nname: Word Wolf\n"
    #expect(ScenarioYAMLLanguage.parse(yaml) == "en")
  }

  @Test func parseReturnsJaForJapaneseLanguageField() {
    let yaml = "id: word_wolf\nlanguage: ja\nname: ワードウルフ\n"
    #expect(ScenarioYAMLLanguage.parse(yaml) == "ja")
  }

  /// Phase 1 convention — malformed YAML keeps the consumer's row
  /// visible by falling back to `"ja"` rather than silently dropping
  /// the record. Mirrors `HomeViewModel.presetsResolvedForLanguageMalformedYamlFallsBackToJa`.
  @Test func parseFallsBackToJaOnMalformedYAML() {
    #expect(ScenarioYAMLLanguage.parse("\t\tnot: [valid: yaml::") == "ja")
  }

  @Test func parseFallsBackToJaWhenLanguageKeyMissing() {
    let yaml = "id: word_wolf\nname: Word Wolf\n"
    #expect(ScenarioYAMLLanguage.parse(yaml) == "ja")
  }

  @Test func parseFallsBackToJaWhenLanguageValueIsNotString() {
    let yaml = "id: word_wolf\nlanguage: 42\nname: Word Wolf\n"
    #expect(ScenarioYAMLLanguage.parse(yaml) == "ja")
  }
}
