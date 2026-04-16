import Foundation

/// Bundles the read-only parameters passed to every phase handler.
///
/// Groups ``Scenario``, ``Phase``, ``LLMService``, the event emitter, and a
/// ``SuspendController`` so that ``PhaseHandler/execute(context:state:)``
/// takes only two parameters.
///
/// `suspendController` is a pass-through for ``LLMCaller`` only. Handlers
/// should not interact with it directly — just forward it to `LLMCaller.call`.
nonisolated public struct PhaseContext: Sendable {
  public let scenario: Scenario
  public let phase: Phase
  public let llm: LLMService
  public let suspendController: SuspendController
  public let emitter: @Sendable (SimulationEvent) -> Void

  public init(
    scenario: Scenario, phase: Phase,
    llm: LLMService,
    suspendController: SuspendController,
    emitter: @escaping @Sendable (SimulationEvent) -> Void
  ) {
    self.scenario = scenario
    self.phase = phase
    self.llm = llm
    self.suspendController = suspendController
    self.emitter = emitter
  }
}

/// A handler that executes one type of simulation phase.
///
/// Each ``PhaseType`` has a corresponding handler registered in ``PhaseDispatcher``.
/// LLM phases call the LLM service; code phases operate deterministically on state.
nonisolated public protocol PhaseHandler: Sendable {
  /// Execute this phase for the current round.
  ///
  /// - Parameters:
  ///   - context: The read-only phase context (scenario, phase, LLM, emitter).
  ///   - state: The mutable simulation state (modified in place).
  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws
}
