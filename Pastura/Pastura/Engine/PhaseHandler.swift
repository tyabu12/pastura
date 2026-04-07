import Foundation

/// A handler that executes one type of simulation phase.
///
/// Each ``PhaseType`` has a corresponding handler registered in ``PhaseDispatcher``.
/// LLM phases call the LLM service; code phases operate deterministically on state.
nonisolated public protocol PhaseHandler: Sendable {
  /// Execute this phase for the current round.
  ///
  /// - Parameters:
  ///   - scenario: The scenario definition.
  ///   - phase: The phase configuration.
  ///   - state: The mutable simulation state (modified in place).
  ///   - llm: The LLM service for inference (unused by code phases).
  ///   - emitter: Closure to emit simulation events to the stream.
  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws
}
