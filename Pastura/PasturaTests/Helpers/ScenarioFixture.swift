import Foundation

@testable import Pastura

/// Test-only `Scenario` factory with sensible defaults.
///
/// Production `Scenario.init(...)` makes `language` a required named
/// argument (ADR-010 D1) so authoring bugs (forgotten field, locale
/// mismatch) fail at the type-checker. Tests covering the legacy
/// Japanese path account for the bulk of fixture sites; this helper
/// lets them omit the field while English-path tests opt in via
/// `language: "en"`.
///
/// Use directly when the test needs control over multiple fields. For
/// the older "minimal handler test with N agents" pattern, prefer
/// ``makeTestScenario(agentNames:language:rounds:phases:context:extraData:)``
/// in `EngineTestHelpers.swift`.
enum ScenarioFixture {
  static func make(
    id: String = "test",
    name: String = "Test",
    description: String = "A test scenario",
    language: String = "ja",
    simulationLanguage: String? = nil,
    agentCount: Int = 2,
    rounds: Int = 1,
    context: String = "",
    personas: [Persona] = [
      Persona(name: "Alice", description: "A test persona"),
      Persona(name: "Bob", description: "A test persona")
    ],
    phases: [Phase] = [],
    extraData: [String: AnyCodableValue] = [:]
  ) -> Scenario {
    Scenario(
      id: id,
      name: name,
      description: description,
      language: language,
      simulationLanguage: simulationLanguage,
      agentCount: agentCount,
      rounds: rounds,
      context: context,
      personas: personas,
      phases: phases,
      extraData: extraData
    )
  }
}
