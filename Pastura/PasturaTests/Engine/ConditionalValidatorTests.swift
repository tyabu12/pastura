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

  // Regression: sub-phase semantic checks (e.g. assign target/source shape)
  // must run inside conditional branches, not only at the top level.
  @Test func rejectsAssignShapeMismatchInThenBranch() {
    let scenario = Scenario(
      id: "t", name: "T", description: "t",
      agentCount: 2, rounds: 1, context: "c",
      personas: [
        Persona(name: "A", description: "a"),
        Persona(name: "B", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            // target .all with arrayOfDictionaries source is the exact
            // shape bug `validateAssignPhaseShape` exists to catch.
            Phase(type: .assign, source: "topics", target: .all)
          ]
        )
      ],
      extraData: [
        "topics": .arrayOfDictionaries([
          ["majority": "cat", "minority": "dog"]
        ])
      ]
    )
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  // event_inject is allowed inside a conditional branch (consistent with
  // assign / score_calc nesting). The validator applies the same
  // shape-check it does at the top level.

  @Test func acceptsEventInjectInThenBranch() throws {
    let scenario = Scenario(
      id: "t", name: "T", description: "t",
      agentCount: 2, rounds: 1, context: "c",
      personas: [
        Persona(name: "A", description: "a"),
        Persona(name: "B", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            Phase(type: .eventInject, source: "events", probability: 0.5)
          ]
        )
      ],
      extraData: ["events": .array(["x", "y"])]
    )
    _ = try validator.validate(scenario)
  }

  @Test func rejectsEventInjectInThenBranchWithMissingSource() {
    let scenario = Scenario(
      id: "t", name: "T", description: "t",
      agentCount: 2, rounds: 1, context: "c",
      personas: [
        Persona(name: "A", description: "a"),
        Persona(name: "B", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            // source key absent from extraData — should fail with the same
            // "not found" message we'd see at the top level, prefixed with
            // the branch label.
            Phase(type: .eventInject, source: "missing_events", probability: 1.0)
          ]
        )
      ]
    )
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw for nested event_inject with missing source")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("then[1]"))
      #expect(message.contains("'missing_events'"))
      #expect(message.contains("not found"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func rejectsEventInjectInElseBranchWithProbabilityOutOfRange() {
    let scenario = Scenario(
      id: "t", name: "T", description: "t",
      agentCount: 2, rounds: 1, context: "c",
      personas: [
        Persona(name: "A", description: "a"),
        Persona(name: "B", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 99",
          thenPhases: [Phase(type: .summarize, template: "ok")],
          elsePhases: [
            Phase(type: .eventInject, source: "events", probability: 2.0)
          ]
        )
      ],
      extraData: ["events": .array(["x"])]
    )
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw for nested event_inject with bad probability")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("else[1]"))
      #expect(message.contains("out of range"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
