import Testing

@testable import Pastura

/// whisper is NOT allowed inside a conditional branch in v1. The validator
/// rejects it at load-time (mirroring the nested-conditional and reflect
/// rejections) so it fails here rather than at `ConditionalHandler` dispatch.
/// Split into a sibling extension (not a new `@Suite`) per
/// `.claude/rules/testing.md` so it shares `ConditionalValidatorTests`'s
/// serialization and keeps the main file under the `type_body_length` cap.
extension ConditionalValidatorTests {

  @Test func rejectsWhisperInThenBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [
          Phase(type: .whisper, prompt: "Whisper.", outputSchema: ["statement": "string"])
        ]
      )
    ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsWhisperInElseBranch() {
    let scenario = makeScenario(phases: [
      Phase(
        type: .conditional,
        condition: "current_round == 1",
        thenPhases: [Phase(type: .summarize, template: "ok")],
        elsePhases: [
          Phase(type: .whisper, prompt: "Whisper.", outputSchema: ["statement": "string"])
        ]
      )
    ])
    do {
      _ = try validator.validate(scenario)
      Issue.record("Expected validation to throw for whisper inside a conditional branch")
    } catch let SimulationError.scenarioValidationFailed(message) {
      #expect(message.contains("else[1]"))
      #expect(message.contains("whisper"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
