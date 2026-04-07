import Foundation

/// Handles `score_calc` phases by dispatching to built-in scoring logics.
///
/// Switches on `phase.logic` to delegate to the appropriate scoring implementation.
nonisolated struct ScoreCalcHandler: PhaseHandler {

  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    guard let logic = phase.logic else {
      throw SimulationError.scenarioValidationFailed(
        "score_calc phase missing 'logic' field"
      )
    }

    switch logic {
    case .prisonersDilemma:
      PrisonersDilemmaLogic().calculate(state: &state, emitter: emitter)
    case .voteTally:
      VoteTallyLogic().calculate(state: &state, emitter: emitter)
    case .wordwolfJudge:
      WordwolfJudgeLogic().calculate(state: &state, emitter: emitter)
    }
  }
}
