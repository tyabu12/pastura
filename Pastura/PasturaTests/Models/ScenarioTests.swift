import Foundation
import Testing

@testable import Pastura

/// Unit tests for the pure-logic surface of ``Scenario``.
///
/// ``Scenario.engineLanguage`` is the single Engine-consumer resolver
/// per ADR-010 D5 + D6 row 1 — the override Site E PR1 wires through
/// PromptBuilder / phase handlers / scoring summaries. These tests
/// pin the precedence shape (`simulationLanguage ?? language`) so
/// future amendments must update both the property and the tests
/// together.
@Suite(.timeLimit(.minutes(1)))
struct ScenarioTests {

  // MARK: - engineLanguage precedence (ADR-010 D5 / D6 row 1)

  @Test func engineLanguageReturnsLanguageWhenSimulationLanguageNil() {
    let scenario = ScenarioFixture.make(language: "ja", simulationLanguage: nil)
    #expect(scenario.engineLanguage == "ja")
  }

  @Test func engineLanguageReturnsLanguageWhenSimulationLanguageNilEn() {
    let scenario = ScenarioFixture.make(language: "en", simulationLanguage: nil)
    #expect(scenario.engineLanguage == "en")
  }

  @Test func engineLanguageOverridesWhenSimulationLanguageSet() {
    // The canonical Step E case: en scenario rendered in ja for cross-language sim.
    let scenario = ScenarioFixture.make(language: "en", simulationLanguage: "ja")
    #expect(scenario.engineLanguage == "ja")
  }

  @Test func engineLanguageOverridesReverse() {
    let scenario = ScenarioFixture.make(language: "ja", simulationLanguage: "en")
    #expect(scenario.engineLanguage == "en")
  }

  // MARK: - acceptedLanguages contract (ADR-010 D1)

  @Test func acceptedLanguagesPinsJaAndEn() {
    #expect(Scenario.acceptedLanguages == ["ja", "en"])
  }
}
