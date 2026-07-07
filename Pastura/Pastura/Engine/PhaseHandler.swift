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
  /// `[K, N]`. Handlers that dispatch nested sub-phases (conditional today)
  /// must append the sub-phase index when constructing lifecycle events for
  /// the inner work.
  public let phasePath: [Int]

  /// Optional language detector used by ``LLMCaller`` for ADR-010 Step E PR2
  /// adherence enforcement. `nil` (the default) disables the check — the
  /// retry budget is then consumed only by `parse_failed` / `empty_field`,
  /// matching pre-Step E PR2 behaviour. Handlers forward this to
  /// `llmCaller.call(detector:expectedLanguage:)` alongside
  /// `context.scenario.engineLanguage`.
  public let detector: (any LanguageDetector)?

  /// Injected logging seam. Handlers emit diagnostics through this instead
  /// of importing OSLog directly, keeping the Engine portable for the KMP
  /// migration (#501 S0.2). Defaults to ``NoopEngineLogger`` so Engine unit
  /// tests and the ADR-013 harness construct contexts without wiring OSLog;
  /// production injects the OSLog-backed logger at the `SimulationRunner`
  /// boundary (see `SimulationView`). Handlers running nested sub-phases must
  /// forward it into the sub-context (`ConditionalHandler`).
  public let logger: any EngineLogger

  /// Run-scoped turn-failure containment gate (ADR-021). LLM handlers wrap
  /// each per-agent `LLMCaller.call` in ``TurnFailureGate/attempt`` so a
  /// transient failure skips the turn instead of aborting the run.
  /// Deliberately NO default value: a fresh gate per context would reset
  /// the run-scoped consecutive-skip counter, so every construction site
  /// must pass the runner's instance explicitly — sub-phase dispatchers
  /// (`ConditionalHandler`) thread the parent context's gate.
  public let turnGate: TurnFailureGate

  public init(
    scenario: Scenario, phase: Phase,
    llm: LLMService,
    suspendController: SuspendController,
    emitter: @escaping @Sendable (SimulationEvent) -> Void,
    pauseCheck: @escaping @Sendable (_ phasePath: [Int]) async -> Bool,
    phasePath: [Int],
    turnGate: TurnFailureGate,
    detector: (any LanguageDetector)? = nil,
    logger: any EngineLogger = NoopEngineLogger()
  ) {
    self.scenario = scenario
    self.phase = phase
    self.llm = llm
    self.suspendController = suspendController
    self.emitter = emitter
    self.pauseCheck = pauseCheck
    self.phasePath = phasePath
    self.turnGate = turnGate
    self.detector = detector
    self.logger = logger
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
