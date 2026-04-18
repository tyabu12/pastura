import Foundation

/// Bundles the read-only parameters passed to every phase handler.
///
/// Groups ``Scenario``, ``Phase``, ``LLMService``, the event emitter, a
/// ``SuspendController``, and a pause-check hook so that
/// ``PhaseHandler/execute(context:state:)`` takes only two parameters.
///
/// `suspendController` is a pass-through for ``LLMCaller`` only. Handlers
/// should not interact with it directly — just forward it to `LLMCaller.call`.
///
/// `pauseCheck` is a narrow bridge onto ``SimulationRunner``'s internal
/// `checkPaused`. Handlers that execute nested sub-phases (e.g. the
/// conditional handler) must call it between each sub-phase so the user's
/// pause request is honored at sub-phase granularity. `.simulationPaused`
/// is emitted by the runner through this hook — handlers must not emit it
/// themselves. The returned `Bool` is `true` when the task was cancelled
/// while paused, in which case the handler should return early.
nonisolated public struct PhaseContext: Sendable {
  public let scenario: Scenario
  public let phase: Phase
  public let llm: LLMService
  public let suspendController: SuspendController
  public let emitter: @Sendable (SimulationEvent) -> Void
  public let pauseCheck: @Sendable (_ phasePath: [Int]) async -> Bool

  /// The path identifying this handler's position in the scenario. Top-level
  /// handlers run with `[K]`; sub-phases inside a conditional run with
  /// `[K, N]`. Handlers that dispatch nested sub-phases (conditional today,
  /// event_inject / reflect tomorrow) must append the sub-phase index when
  /// constructing lifecycle events for the inner work.
  public let phasePath: [Int]

  public init(
    scenario: Scenario, phase: Phase,
    llm: LLMService,
    suspendController: SuspendController,
    emitter: @escaping @Sendable (SimulationEvent) -> Void,
    pauseCheck: @escaping @Sendable (_ phasePath: [Int]) async -> Bool,
    phasePath: [Int]
  ) {
    self.scenario = scenario
    self.phase = phase
    self.llm = llm
    self.suspendController = suspendController
    self.emitter = emitter
    self.pauseCheck = pauseCheck
    self.phasePath = phasePath
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
