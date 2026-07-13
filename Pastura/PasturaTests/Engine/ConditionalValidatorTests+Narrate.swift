import Testing

@testable import Pastura

/// narrate is NOT allowed inside a conditional branch in v1 (#909). The
/// validator rejects it at load-time (mirroring the reflect / whisper /
/// relationship_update rejections) so it fails at the load gate rather than
/// mid-run at `ConditionalHandler` dispatch (which omits narrate from its
/// sub-handler map). Split into a sibling extension (not a new `@Suite`) per
/// `.claude/rules/testing.md`.
extension ConditionalValidatorTests {

  @Test func rejectsNarrateInThenBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .narrate, prompt: "Narrate.")]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsNarrateInElseBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "ok")],
        elsePhases: [Phase(type: .narrate, prompt: "Narrate.")]
      )
    ])
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw for narrate inside a conditional branch")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("else[1]"))
      #expect(message.contains("narrate"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
