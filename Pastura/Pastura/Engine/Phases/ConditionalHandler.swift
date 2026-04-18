import Foundation

/// Handles `conditional` phases — evaluates a DSL expression against the
/// current simulation state and dispatches to `thenPhases` or `elsePhases`.
///
/// Owns a private ``PhaseDispatcher`` so the outer runner's dispatcher is
/// not threaded through ``PhaseContext``. ``SimulationRunner`` remains the
/// sole emitter of `.simulationPaused`; this handler invokes
/// `context.pauseCheck` between each sub-phase so the user's pause request
/// is honored at sub-phase granularity.
///
/// Nested lifecycle events (`phaseStarted` / `phaseCompleted`) are emitted
/// with paths of the form `[outerK, innerN]` so consumers can tell a nested
/// phase apart from a top-level phase of the same `phaseType`. The outer
/// `.phaseStarted(.conditional, ...)` / `.phaseCompleted(.conditional, ...)`
/// are emitted by the runner — the handler does NOT emit them itself.
///
/// Runtime-absent condition variables (e.g. `vote_winner` before any vote
/// runs this round) produce `value: false` plus a warning string that this
/// handler forwards to the `.summary` event channel.
nonisolated struct ConditionalHandler: PhaseHandler {
  private let evaluator = ConditionEvaluator()

  /// Sub-phase handlers that the conditional's branches may contain.
  ///
  /// Deliberately omits `.conditional` itself — that enforces the depth-1
  /// rule at runtime (if a nested conditional somehow slipped past the
  /// validator, dispatch throws here) and also avoids the initialization
  /// cycle that would otherwise occur: a `PhaseDispatcher` contains every
  /// handler, including `ConditionalHandler`, which would build another
  /// `PhaseDispatcher` in turn, forever.
  private let subHandlers: [PhaseType: any PhaseHandler] = [
    .speakAll: SpeakAllHandler(),
    .speakEach: SpeakEachHandler(),
    .vote: VoteHandler(),
    .choose: ChooseHandler(),
    .scoreCalc: ScoreCalcHandler(),
    .assign: AssignHandler(),
    .eliminate: EliminateHandler(),
    .summarize: SummarizeHandler()
  ]

  init() {}

  func execute(context: PhaseContext, state: inout SimulationState) async throws {
    let expression = context.phase.condition ?? ""
    let evaluation = try evaluator.evaluate(
      expression, state: state, scenario: context.scenario)

    for warning in evaluation.warnings {
      context.emitter(.summary(text: "⚠️ \(warning)"))
    }

    context.emitter(
      .conditionalEvaluated(condition: expression, result: evaluation.value))

    let branch =
      evaluation.value
      ? (context.phase.thenPhases ?? [])
      : (context.phase.elsePhases ?? [])

    try await runBranch(branch, context: context, state: &state)
  }

  /// Runs the selected branch's sub-phases, threading pause checks and
  /// lifecycle events through at `[outerK, innerN]` paths.
  private func runBranch(
    _ phases: [Phase], context: PhaseContext, state: inout SimulationState
  ) async throws {
    for (innerIndex, subPhase) in phases.enumerated() {
      if Task.isCancelled {
        return
      }

      let innerPath = context.phasePath + [innerIndex]
      if await context.pauseCheck(innerPath) {
        return
      }

      context.emitter(.phaseStarted(phaseType: subPhase.type, phasePath: innerPath))

      // Scope each sub-phase's context to itself — the dispatcher resolves
      // a handler based on `phase.type`, and the sub-handler sees the
      // nested path as its own `phasePath`.
      let subContext = PhaseContext(
        scenario: context.scenario,
        phase: subPhase,
        llm: context.llm,
        suspendController: context.suspendController,
        emitter: context.emitter,
        pauseCheck: context.pauseCheck,
        phasePath: innerPath
      )

      guard let handler = subHandlers[subPhase.type] else {
        throw SimulationError.scenarioValidationFailed(
          "Phase type '\(subPhase.type.rawValue)' is not allowed inside a "
            + "conditional branch (depth-1 rule)."
        )
      }
      try await handler.execute(context: subContext, state: &state)

      context.emitter(.phaseCompleted(phaseType: subPhase.type, phasePath: innerPath))
    }
  }
}
