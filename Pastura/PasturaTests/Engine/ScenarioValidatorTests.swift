import Testing

@testable import Pastura

struct ScenarioValidatorTests {
  let validator = ScenarioValidator()

  @Test func acceptsValidScenario() throws {
    let scenario = makeScenario(agents: 5, rounds: 3, phases: [Phase(type: .speakAll)])
    let result = try validator.validate(scenario)
    #expect(result.warnings.isEmpty)
  }

  @Test func rejectsZeroAgents() {
    let scenario = makeScenario(agents: 0, rounds: 1, phases: [Phase(type: .speakAll)])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsSingleAgent() {
    let scenario = makeScenario(agents: 1, rounds: 1, phases: [Phase(type: .speakAll)])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func acceptsExactlyTwoAgents() throws {
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [Phase(type: .speakAll)])
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

  @Test func rejectsPersonaCountMismatch() {
    // Constructed directly because makeScenario auto-generates matching personas
    let scenario = Scenario(
      id: "test", name: "Test", description: "Test",
      agentCount: 3, rounds: 1, context: "Context",
      personas: [Persona(name: "A", description: "D"), Persona(name: "B", description: "D")],
      phases: [Phase(type: .speakAll)]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  // MARK: - Assign phase: target "all" (or nil) shape checks
  // Unknown-target rejection now lives in ScenarioLoaderTests (caught at parse).

  @Test func acceptsAssignAllWithStringSource() throws {
    let scenario = makeAssignScenario(
      target: .all, source: "topic",
      extraData: ["topic": .string("Hi")]
    )
    _ = try validator.validate(scenario)
  }

  @Test func acceptsAssignAllWithArraySource() throws {
    let scenario = makeAssignScenario(
      target: .all, source: "topics",
      extraData: ["topics": .array(["A", "B"])]
    )
    _ = try validator.validate(scenario)
  }

  @Test func acceptsAssignAllWithMissingSourceKey() throws {
    // Visual Editor compat: extraData is empty, skip shape check
    let scenario = makeAssignScenario(target: .all, source: "topics", extraData: [:])
    _ = try validator.validate(scenario)
  }

  @Test func acceptsAssignAllWithNilSource() throws {
    // Visual Editor compat: no source specified, skip shape check
    let scenario = makeAssignScenario(target: .all, source: nil, extraData: [:])
    _ = try validator.validate(scenario)
  }

  @Test func acceptsAssignWithDefaultTarget() throws {
    // nil target defaults to .all behaviour; valid array source should pass
    let scenario = makeAssignScenario(
      target: nil, source: "topics",
      extraData: ["topics": .array(["A", "B"])]
    )
    _ = try validator.validate(scenario)
  }

  @Test func rejectsAssignAllWithArrayOfDictionariesSource() {
    let scenario = makeAssignScenario(
      target: .all, source: "words",
      extraData: ["words": .arrayOfDictionaries([["majority": "x", "minority": "y"]])]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsAssignAllWithDictionarySource() {
    let scenario = makeAssignScenario(
      target: .all, source: "w",
      extraData: ["w": .dictionary(["a": "b"])]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  /// User-facing error must include 1-based phase index and source key
  /// — these end up in editor / import UI verbatim.
  @Test func rejectAssignAllWithBadShapeIncludesPhaseIndexAndSourceKey() {
    let scenario = makeAssignScenario(
      target: .all, source: "words",
      extraData: ["words": .arrayOfDictionaries([["majority": "x", "minority": "y"]])]
    )
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("Phase 1 (assign)"))
      #expect(message.contains("'words'"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  // MARK: - Assign phase: target "random_one" shape checks

  @Test func acceptsAssignRandomOneWithArrayOfDictionariesSource() throws {
    let scenario = makeAssignScenario(
      target: .randomOne, source: "words",
      extraData: ["words": .arrayOfDictionaries([["majority": "x", "minority": "y"]])]
    )
    _ = try validator.validate(scenario)
  }

  @Test func rejectsAssignRandomOneWithArraySource() {
    let scenario = makeAssignScenario(
      target: .randomOne, source: "topics",
      extraData: ["topics": .array(["A", "B"])]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsAssignRandomOneWithStringSource() {
    let scenario = makeAssignScenario(
      target: .randomOne, source: "topic",
      extraData: ["topic": .string("Hi")]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func acceptsAssignRandomOneWithMissingSourceKey() throws {
    // Visual Editor compat: extraData is empty, skip shape check
    let scenario = makeAssignScenario(target: .randomOne, source: "words", extraData: [:])
    _ = try validator.validate(scenario)
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

  private func makeAssignScenario(
    target: AssignTarget?,
    source: String?,
    extraData: [String: AnyCodableValue]
  ) -> Scenario {
    Scenario(
      id: "test", name: "Test", description: "Test",
      agentCount: 2, rounds: 1, context: "Context",
      personas: [Persona(name: "A", description: "D"), Persona(name: "B", description: "D")],
      phases: [Phase(type: .assign, source: source, target: target)],
      extraData: extraData
    )
  }
}
