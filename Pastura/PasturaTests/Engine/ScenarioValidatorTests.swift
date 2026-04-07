import Testing

@testable import Pastura

struct ScenarioValidatorTests {
  let validator = ScenarioValidator()

  @Test func acceptsValidScenario() throws {
    let scenario = makeScenario(agents: 5, rounds: 3, phases: [Phase(type: .speakAll)])
    let result = try validator.validate(scenario)
    #expect(result.warnings.isEmpty)
  }

  @Test func rejectsMoreThan10Agents() {
    let scenario = makeScenario(agents: 11, rounds: 1, phases: [Phase(type: .speakAll)])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsMoreThan30Rounds() {
    let scenario = makeScenario(agents: 2, rounds: 31, phases: [Phase(type: .speakAll)])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func warnsWhenInferencesExceed50() throws {
    // 10 agents × (speak_all + vote) × 3 rounds = 60
    let scenario = makeScenario(
      agents: 10, rounds: 3,
      phases: [Phase(type: .speakAll), Phase(type: .vote)]
    )
    let result = try validator.validate(scenario)
    #expect(!result.warnings.isEmpty)
    #expect(result.estimatedInferences == 60)
  }

  @Test func errorsWhenInferencesExceed100() {
    // 10 agents × (speak_all + speak_each(3) + vote) × 3 rounds = 150
    let scenario = makeScenario(
      agents: 10, rounds: 3,
      phases: [
        Phase(type: .speakAll),
        Phase(type: .speakEach, subRounds: 3),
        Phase(type: .vote)
      ]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func returnsEstimatedInferences() throws {
    let scenario = makeScenario(
      agents: 5, rounds: 2,
      phases: [Phase(type: .speakAll), Phase(type: .vote)]
    )
    let result = try validator.validate(scenario)
    #expect(result.estimatedInferences == 20)
  }

  // MARK: - Helpers

  private func makeScenario(agents: Int, rounds: Int, phases: [Phase]) -> Scenario {
    Scenario(
      id: "test", name: "Test", description: "Test",
      agentCount: agents, rounds: rounds, context: "Context",
      personas: (0..<agents).map { Persona(name: "A\($0)", description: "D") },
      phases: phases
    )
  }
}
