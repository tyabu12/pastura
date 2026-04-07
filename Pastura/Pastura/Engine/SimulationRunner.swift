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

  private static func executeSimulation(
    scenario: Scenario,
    llm: LLMService,
    dispatcher: PhaseDispatcher,
    validator: ScenarioValidator,
    isPausedLock: OSAllocatedUnfairLock<Bool>,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async {
    // Validate scenario
    let validationResult: ScenarioValidator.ValidationResult
    do {
      validationResult = try validator.validate(scenario)
    } catch {
      if let simError = error as? SimulationError {
        emitter(.error(simError))
      } else {
        emitter(.error(.scenarioValidationFailed("\(error)")))
      }
      return
    }

    // Emit warnings
    for warning in validationResult.warnings {
      emitter(.summary(text: "⚠️ \(warning)"))
    }

    // Initialize state
    var state = SimulationState.initial(for: scenario)

    // Round loop
    for round in 1...scenario.rounds {
      // Check cancellation
      if Task.isCancelled {
        emitter(.error(.cancelled))
        return
      }

      // Check pause
      while isPausedLock.withLock({ $0 }) {
        emitter(.simulationPaused(round: round, phaseIndex: 0))
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          // Task cancelled during sleep
          emitter(.error(.cancelled))
          return
        }
      }

      // Check active agent count
      let activeCount = state.eliminated.values.filter { !$0 }.count
      if activeCount < 2 {
        break
      }

      // Reset per-round state (matching prototype behavior)
      state.conversationLog = []
      state.pairings = []
      state.currentRound = round
      state.variables["current_round"] = "\(round)"

      emitter(.roundStarted(round: round, totalRounds: scenario.rounds))

      // Phase loop
      for (phaseIndex, phase) in scenario.phases.enumerated() {
        if Task.isCancelled {
          emitter(.error(.cancelled))
          return
        }

        emitter(.phaseStarted(phaseType: phase.type, phaseIndex: phaseIndex))

        do {
          let handler = try dispatcher.handler(for: phase.type)
          try await handler.execute(
            scenario: scenario, phase: phase, state: &state,
            llm: llm, emitter: emitter
          )
        } catch {
          if let simError = error as? SimulationError {
            emitter(.error(simError))
          } else {
            emitter(.error(.llmGenerationFailed(description: "\(error)")))
          }
          return
        }

        emitter(.phaseCompleted(phaseType: phase.type, phaseIndex: phaseIndex))
      }

      emitter(.roundCompleted(round: round, scores: state.scores))
    }

    emitter(.simulationCompleted)
  }
}
