import Testing

@testable import Pastura

/// relationship_update is NOT allowed inside a conditional branch in v1. The
/// validator rejects it at load-time (mirroring the nested-conditional,
/// reflect, and whisper rejections) so it fails here rather than at
/// `ConditionalHandler` dispatch — where it is also absent from `subHandlers`
/// as a structural backstop. Split into a sibling extension (not a new
/// `@Suite`) per `.claude/rules/testing.md` so it shares
/// `ConditionalValidatorTests`'s serialization and keeps the main file under
/// the `type_body_length` cap.
extension ConditionalValidatorTests {

  @Test func rejectsRelationshipUpdateInThenBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .relationshipUpdate, voteAgainst: -1)]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsRelationshipUpdateInElseBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "ok")],
        elsePhases: [Phase(type: .relationshipUpdate, actionDeltas: ["cooperate": 1])]
      )
    ])
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw for relationship_update inside a conditional")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("else[1]"))
      #expect(message.contains("relationship_update"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
