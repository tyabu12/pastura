import Foundation

/// Handles `score_calc` phases by dispatching to built-in scoring logics.
///
/// Switches on `phase.logic` to delegate to the appropriate scoring implementation.
nonisolated struct ScoreCalcHandler: PhaseHandler {

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    guard let logic = context.phase.logic else {
      throw SimulationError.scenarioValidationFailed(
        "score_calc phase missing 'logic' field"
      )
    }

    switch logic {
    case .prisonersDilemma:
      PrisonersDilemmaLogic().calculate(state: &state, emitter: context.emitter)
    case .voteTally:
      VoteTallyLogic().calculate(state: &state, emitter: context.emitter)
    case .wordwolfJudge:
      WordwolfJudgeLogic().calculate(state: &state, emitter: context.emitter)
    }
  }
}
