import Foundation

/// Routes ``PhaseType`` values to their corresponding ``PhaseHandler`` implementations.
///
/// All 8 phase types are registered at initialization. Used by ``SimulationRunner``
/// to dispatch each phase in the simulation loop.
nonisolated struct PhaseDispatcher: Sendable {
  private let handlers: [PhaseType: any PhaseHandler]

  init() {
    handlers = [
      .speakAll: SpeakAllHandler(),
      .speakEach: SpeakEachHandler(),
      .vote: VoteHandler(),
      .choose: ChooseHandler(),
      .scoreCalc: ScoreCalcHandler(),
      .assign: AssignHandler(),
      .eliminate: EliminateHandler(),
      .summarize: SummarizeHandler()
    ]
  }

  /// Returns the handler for the given phase type.
  ///
  /// - Parameter phaseType: The type of phase to handle.
  /// - Returns: The corresponding ``PhaseHandler`` implementation.
  /// - Throws: ``SimulationError/scenarioValidationFailed(_:)`` if no handler is registered.
  func handler(for phaseType: PhaseType) throws -> any PhaseHandler {
    guard let handler = handlers[phaseType] else {
      throw SimulationError.scenarioValidationFailed(
        "No handler registered for phase type: \(phaseType.rawValue)"
      )
    }
    return handler
  }
}
