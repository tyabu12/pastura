import Testing

@testable import Pastura

// Pre-flight parse-time validation for conditional `if:` expressions.
// These cases ensure that malformed expressions surface at scenario-load
// time (validator), not mid-simulation when the handler dispatches —
// critical for gallery curation where curated scenarios must fail before
// shipping. Sibling extension per .claude/rules/testing.md.

extension ConditionalValidatorTests {
  @Test func rejectsMalformedConditionAtValidateTime() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "(current_round == 1 && max_score > 0",
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsDanglingCombinatorAtValidateTime() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1 &&",
        thenPhases: [Phase(type: .summarize, template: "t")]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }
}
