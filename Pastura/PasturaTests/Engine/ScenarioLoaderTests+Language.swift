import Testing

@testable import Pastura

extension ScenarioLoaderTests {

  // MARK: - language field (DoD #2, #5, #6)

  private func makeBaseYAML(language: String? = nil, simulationLanguage: String? = nil) -> String {
    var lines = [
      "id: t"
    ]
    if let language {
      lines.append("language: \(language)")
    }
    if let simulationLanguage {
      lines.append("simulation_language: \(simulationLanguage)")
    }
    lines += [
      "name: T",
      "description: T",
      "agents: 2",
      "rounds: 1",
      "context: C",
      "personas:",
      "  - name: A",
      "    description: D",
      "  - name: B",
      "    description: D",
      "phases:",
      "  - type: speak_all",
      "    prompt: x",
      "    output:",
      "      statement: string"
    ]
    return lines.joined(separator: "\n")
  }

  @Test func rejectsLanguageAbsent() {
    let yaml = makeBaseYAML()  // no language: line
    do {
      _ = try loader.load(yaml: yaml)
      Issue.record("Expected load to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("language"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func parsesLanguageJa() throws {
    let yaml = makeBaseYAML(language: "ja")
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.language == "ja")
  }

  @Test func parsesLanguageEn() throws {
    let yaml = makeBaseYAML(language: "en")
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.language == "en")
  }

  @Test func rejectsLanguageInvalid() {
    let yaml = makeBaseYAML(language: "fr")
    do {
      _ = try loader.load(yaml: yaml)
      Issue.record("Expected load to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("language"))
      #expect(message.contains("fr"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func parsesSimulationLanguageEn() throws {
    let yaml = makeBaseYAML(language: "ja", simulationLanguage: "en")
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.simulationLanguage == "en")
  }

  @Test func simulationLanguageAbsent() throws {
    let yaml = makeBaseYAML(language: "ja")
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.simulationLanguage == nil)
  }

  @Test func rejectsSimulationLanguageInvalid() {
    let yaml = makeBaseYAML(language: "ja", simulationLanguage: "fr")
    do {
      _ = try loader.load(yaml: yaml)
      Issue.record("Expected load to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("simulation_language"))
      #expect(message.contains("fr"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }
}
