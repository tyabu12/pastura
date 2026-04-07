import Foundation
import os

/// Orchestrates simulation execution, emitting events via `AsyncStream`.
///
/// Validates the scenario, initializes state, then loops through rounds and phases,
/// dispatching each phase to the appropriate handler. Supports pause/resume via
/// `isPaused` flag and cancellation via Swift `Task` cancellation.
nonisolated public final class SimulationRunner: @unchecked Sendable {
  // @unchecked Sendable: mutable isPaused is protected by OSAllocatedUnfairLock.

  private let isPausedLock = OSAllocatedUnfairLock(initialState: false)
  private let dispatcher = PhaseDispatcher()
  private let validator = ScenarioValidator()

  public init() {}

  /// Whether the simulation is currently paused.
  public var isPaused: Bool {
    get { isPausedLock.withLock { $0 } }
    set { isPausedLock.withLock { $0 = newValue } }
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
    let isPausedLock = self.isPausedLock

    return AsyncStream { continuation in
      let task = Task {
        await Self.executeSimulation(
          scenario: scenario, llm: llm,
          dispatcher: dispatcher, validator: validator,
          isPausedLock: isPausedLock,
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
    let isPausedLock: OSAllocatedUnfairLock<Bool>
    let emitter: @Sendable (SimulationEvent) -> Void
  }

  // swiftlint:disable:next function_parameter_count
  private static func executeSimulation(
    scenario: Scenario, llm: LLMService,
    dispatcher: PhaseDispatcher, validator: ScenarioValidator,
    isPausedLock: OSAllocatedUnfairLock<Bool>,
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
      isPausedLock: isPausedLock, emitter: emitter
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
      if activeCount < 2 { break }

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

  /// Returns `true` if cancelled during pause wait.
  // TODO: Emit simulationPaused only once instead of every 100ms poll cycle
  // to reduce event volume. UI layer should handle the single event. (#20)
  private static func checkPaused(ctx: ExecutionContext, round: Int) async -> Bool {
    while ctx.isPausedLock.withLock({ $0 }) {
      ctx.emitter(.simulationPaused(round: round, phaseIndex: 0))
      do {
        try await Task.sleep(for: .milliseconds(100))
      } catch {
        ctx.emitter(.error(.cancelled))
        return true
      }
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
        try await handler.execute(
          scenario: ctx.scenario, phase: phase, state: &state,
          llm: ctx.llm, emitter: ctx.emitter
        )
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
