import Testing

@testable import Pastura

/// reflect is NOT allowed inside a conditional branch in v1. The validator
/// rejects it at load-time (mirroring the nested-conditional rejection) so it
/// fails here rather than at `ConditionalHandler` dispatch. Split into a
/// sibling extension (not a new `@Suite`) per `.claude/rules/testing.md` so it
/// shares `ConditionalValidatorTests`'s serialization and keeps the main file
/// under the `type_body_length` cap.
extension ConditionalValidatorTests {

  @Test func rejectsReflectInThenBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [
          Phase(type: .reflect, prompt: "Reflect.", outputSchema: ["note": "string"])
        ]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsReflectInElseBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "ok")],
        elsePhases: [
          Phase(type: .reflect, prompt: "Reflect.", outputSchema: ["note": "string"])
        ]
      )
    ])
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw for reflect inside a conditional branch")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("else[1]"))
      #expect(message.contains("reflect"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
