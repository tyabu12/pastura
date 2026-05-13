import Testing

@testable import Pastura

extension ScenarioValidatorTests {

  // MARK: - language + simulationLanguage validation (DoD #2, #5)

  @Test func rejectsInvalidLanguage() {
    let scenario = ScenarioFixture.make(language: "fr")
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("language"))
      #expect(message.contains("fr"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func rejectsInvalidSimulationLanguage() {
    let scenario = ScenarioFixture.make(simulationLanguage: "fr")
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("simulationLanguage"))
      #expect(message.contains("fr"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func acceptsValidJa() throws {
    let scenario = ScenarioFixture.make(language: "ja")
    _ = try validator.validate(scenario)
  }

  @Test func acceptsValidEn() throws {
    let scenario = ScenarioFixture.make(language: "en")
    _ = try validator.validate(scenario)
  }

  @Test func acceptsNilSimulationLanguage() throws {
    let scenario = ScenarioFixture.make()  // default simulationLanguage: nil
    _ = try validator.validate(scenario)
  }
}
