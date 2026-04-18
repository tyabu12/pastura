import Testing

@testable import Pastura

/// Validator coverage for conditional phases beyond execution-limit checks.
@Suite(.timeLimit(.minutes(1)))
struct ConditionalValidatorTests {
  let validator = ScenarioValidator()

  private func makeScenario(phases: [Phase]) -> Scenario {
    Scenario(
      id: "t", name: "T", description: "t",
      agentCount: 2, rounds: 1, context: "c",
      personas: [Persona(name: "A", description: "a"), Persona(name: "B", description: "b")],
      phases: phases
    )
  }

  @Test func acceptsValidConditional() throws {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    _ = try validator.validate(scenario)
  }

  @Test func rejectsEmptyCondition() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "",
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsMissingCondition() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsWhitespaceOnlyCondition() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "   \n  ",
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsBothBranchesEmpty() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [],
        elsePhases: []
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsBothBranchesNil() {
    let scenario = makeScenario(phases: [
      Phase(type: .conditional, condition: "current_round == 1")
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func acceptsOnlyThenBranch() throws {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    _ = try validator.validate(scenario)
  }

  @Test func acceptsOnlyElseBranch() throws {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        elsePhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    _ = try validator.validate(scenario)
  }

  @Test func rejectsNestedConditionalInThenBranch() {
    // Non-YAML construction path — loader covers the YAML side. This
    // validator check catches scenarios built programmatically (tests,
    // future editors, migrations).
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [
          Phase(type: .conditional, condition: "max_score > 0")
        ]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsNestedConditionalInElseBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "ok")],
        elsePhases: [
          Phase(type: .conditional, condition: "max_score > 0")
        ]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }
}
