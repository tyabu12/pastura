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
      WordwolfJudgeLogic().calculate(
        state: &state, language: context.scenario.engineLanguage, emitter: context.emitter)
    case .eventReactive:
      // v1 uses the companion-variable convention keyed off the default
      // event variable name (`current_event__favors`). Honoring a custom
      // `as:` on the event_inject phase (via a phase-level
      // `favored_variable:` field) is deferred — see #931.
      EventReactivePayoffLogic().calculate(
        state: &state,
        favoredVariable: EventInjectHandler.favoredVariableName(
          for: EventInjectHandler.defaultVariableName),
        emitter: context.emitter)
    }
  }
}
