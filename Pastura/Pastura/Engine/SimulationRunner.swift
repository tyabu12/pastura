import Foundation
import os

/// Orchestrates simulation execution, emitting events via `AsyncStream`.
///
/// Validates the scenario, initializes state, then loops through rounds and phases,
/// dispatching each phase to the appropriate handler. Supports pause/resume via
/// `isPaused` flag and cancellation via Swift `Task` cancellation.
nonisolated public final class SimulationRunner: @unchecked Sendable {
  // @unchecked Sendable: mutable pauseState is protected by OSAllocatedUnfairLock.

  /// Bundles the pause flag and an optional resume continuation in a single lock,
  /// so the setter can atomically detect "unpaused while someone is waiting" and
  /// resume the continuation without a race.
  private struct PauseState: Sendable {
    var isPaused = false
    var resumeContinuation: CheckedContinuation<Void, Never>?
  }

  private let pauseState = OSAllocatedUnfairLock(initialState: PauseState())
  private let dispatcher = PhaseDispatcher()
  private let validator = ScenarioValidator()

  public init() {}

  /// Whether the simulation is currently paused.
  public var isPaused: Bool {
    get { pauseState.withLock { $0.isPaused } }
    set {
      // Extract continuation under lock, resume outside to avoid holding the
      // lock during executor enqueue (lock-discipline best practice).
      let cont: CheckedContinuation<Void, Never>? = pauseState.withLock { state in
        state.isPaused = newValue
        guard !newValue, let c = state.resumeContinuation else { return nil }
        state.resumeContinuation = nil
        return c
      }
      cont?.resume()
    }
  }

  /// Runs a simulation and returns an `AsyncStream` of events.
  ///
  /// The stream emits events as the simulation progresses: round/phase lifecycle,
  /// agent outputs, score updates, and completion/error events. The stream finishes
  /// when the simulation completes, is cancelled, or encounters a fatal error.
  ///
  /// - Parameters:
  ///   - scenario: The scenario to execute.
  ///   - llm: The LLM service for inference.
  /// - Returns: An `AsyncStream` of ``SimulationEvent`` values.
  public func run(scenario: Scenario, llm: LLMService) -> AsyncStream<SimulationEvent> {
    // Capture needed values to avoid retaining self in the Task
    let dispatcher = self.dispatcher
    let validator = self.validator
    let pauseState = self.pauseState

    return AsyncStream { continuation in
      let task = Task {
        await Self.executeSimulation(
          scenario: scenario, llm: llm,
          dispatcher: dispatcher, validator: validator,
          pauseState: pauseState,
          emitter: { continuation.yield($0) }
        )
        continuation.finish()
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  // MARK: - Private

  /// Shared context passed through the simulation execution pipeline.
  private struct ExecutionContext: Sendable {
    let scenario: Scenario
    let llm: LLMService
    let dispatcher: PhaseDispatcher
    let pauseState: OSAllocatedUnfairLock<PauseState>
    let emitter: @Sendable (SimulationEvent) -> Void
  }

  // swiftlint:disable:next function_parameter_count
  private static func executeSimulation(
    scenario: Scenario, llm: LLMService,
    dispatcher: PhaseDispatcher, validator: ScenarioValidator,
    pauseState: OSAllocatedUnfairLock<PauseState>,
    emitter: @escaping @Sendable (SimulationEvent) -> Void
  ) async {
    // Validate scenario
    do {
      let result = try validator.validate(scenario)
      for warning in result.warnings {
        emitter(.summary(text: "⚠️ \(warning)"))
      }
    } catch {
      emitter(.error(error as? SimulationError ?? .scenarioValidationFailed("\(error)")))
      return
    }

    let ctx = ExecutionContext(
      scenario: scenario, llm: llm, dispatcher: dispatcher,
      pauseState: pauseState, emitter: emitter
    )

    var state = SimulationState.initial(for: scenario)
    await runRoundLoop(ctx: ctx, state: &state)
  }

  private static func runRoundLoop(ctx: ExecutionContext, state: inout SimulationState) async {
    for round in 1...ctx.scenario.rounds {
      if Task.isCancelled {
        ctx.emitter(.error(.cancelled))
        return
      }

      if await checkPaused(ctx: ctx, round: round) { return }

      let activeCount = state.eliminated.values.filter { !$0 }.count
      if activeCount < 2 {
        ctx.emitter(.summary(text: "Simulation ended early: fewer than 2 active agents remaining"))
        break
      }

      state.conversationLog = []
      state.pairings = []
      state.currentRound = round
      state.variables["current_round"] = "\(round)"

      ctx.emitter(.roundStarted(round: round, totalRounds: ctx.scenario.rounds))

      if await executePhases(ctx: ctx, state: &state) { return }

      ctx.emitter(.roundCompleted(round: round, scores: state.scores))
    }

    ctx.emitter(.simulationCompleted)
  }

  /// Returns `true` if the task was cancelled while waiting for resume.
  ///
  /// Emits `.simulationPaused` exactly once, then suspends via
  /// `CheckedContinuation` until `isPaused` is set to `false` or the
  /// task is cancelled — no polling, zero CPU during pause.
  private static func checkPaused(ctx: ExecutionContext, round: Int) async -> Bool {
    guard ctx.pauseState.withLock({ $0.isPaused }) else { return false }

    ctx.emitter(.simulationPaused(round: round, phaseIndex: 0))

    // Why withTaskCancellationHandler + withCheckedContinuation:
    // We need to resume the continuation on EITHER unpause (via isPaused setter)
    // or task cancellation (via onCancel). The OSAllocatedUnfairLock serializes
    // all three resume paths (setter, onCancel, and the in-closure isCancelled
    // check) so the continuation is resumed exactly once.
    //
    // Race ordering: onCancel may fire before the continuation is stored. In that
    // case onCancel finds nil and does nothing, but the closure then detects
    // Task.isCancelled inside the lock and resumes immediately.
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let shouldResumeNow = ctx.pauseState.withLock { state in
          if !state.isPaused {
            return true
          }
          state.resumeContinuation = continuation
          // If cancelled between handler registration and here, onCancel found
          // nil. Catch it now while we hold the lock — no one else can resume.
          if Task.isCancelled {
            state.resumeContinuation = nil
            return true
          }
          return false
        }
        if shouldResumeNow {
          continuation.resume()
        }
      }
    } onCancel: {
      // Extract continuation under lock, resume outside (lock discipline).
      let cont: CheckedContinuation<Void, Never>? = ctx.pauseState.withLock { state in
        guard let c = state.resumeContinuation else { return nil }
        state.resumeContinuation = nil
        return c
      }
      cont?.resume()
    }

    if Task.isCancelled {
      ctx.emitter(.error(.cancelled))
      return true
    }
    return false
  }

  /// Returns `true` if an error occurred and the simulation should stop.
  private static func executePhases(ctx: ExecutionContext, state: inout SimulationState) async
    -> Bool {
    for (phaseIndex, phase) in ctx.scenario.phases.enumerated() {
      if Task.isCancelled {
        ctx.emitter(.error(.cancelled))
        return true
      }

      ctx.emitter(.phaseStarted(phaseType: phase.type, phaseIndex: phaseIndex))

      do {
        let handler = try ctx.dispatcher.handler(for: phase.type)
        // PhaseContext bundles the per-phase read-only args from ExecutionContext;
        // ExecutionContext additionally carries dispatcher and isPausedLock which
        // are runner-internal and not exposed to handlers.
        let phaseContext = PhaseContext(
          scenario: ctx.scenario, phase: phase,
          llm: ctx.llm, emitter: ctx.emitter
        )
        try await handler.execute(context: phaseContext, state: &state)
      } catch {
        ctx.emitter(
          .error(error as? SimulationError ?? .llmGenerationFailed(description: "\(error)")))
        return true
      }

      ctx.emitter(.phaseCompleted(phaseType: phase.type, phaseIndex: phaseIndex))
    }
    return false
  }
}
