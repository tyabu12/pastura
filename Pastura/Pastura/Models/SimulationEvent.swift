import Foundation

/// Events emitted by `SimulationRunner` via `AsyncStream`.
///
/// This enum is the contract between Engine, App, and Views layers.
/// The App/ViewModel layer consumes these events to update UI state
/// and persist turn records to the database.
nonisolated public enum SimulationEvent: Sendable, Equatable {
  // MARK: - Round Lifecycle

  /// A new round has started.
  case roundStarted(round: Int, totalRounds: Int)

  /// A round has completed with current scores.
  case roundCompleted(round: Int, scores: [String: Int])

  // MARK: - Phase Lifecycle

  /// A phase is about to begin execution.
  case phaseStarted(phaseType: PhaseType, phaseIndex: Int)

  /// A phase has finished execution.
  case phaseCompleted(phaseType: PhaseType, phaseIndex: Int)

  // MARK: - Agent Outputs (LLM Phases)

  /// An agent produced output from an LLM phase.
  case agentOutput(agent: String, output: TurnOutput, phaseType: PhaseType)

  /// Incremental snapshot of an agent's in-flight LLM output.
  ///
  /// Emitted during token-by-token streaming (see `LLMCaller` + the
  /// streaming ``LLMService/generateStream(system:user:)`` path). Carries
  /// the best-effort partial primary value (e.g., `statement`) and
  /// optional `inner_thought` extracted from the model's still-arriving
  /// JSON response.
  ///
  /// Semantics:
  /// - The event replaces — rather than appends to — the agent's current
  ///   stream snapshot. Consumers overwrite their per-agent buffer on
  ///   each emission.
  /// - `primary == nil` means the primary key's opening quote has not
  ///   yet been observed; the UI should keep the "thinking…" indicator
  ///   visible. Once `primary` becomes non-nil (even as `""`), the
  ///   indicator should yield to the streaming row.
  /// - On retry / suspend re-issue, a new snapshot for the same agent
  ///   naturally overwrites — no separate reset event is required.
  /// - ``agentOutput(agent:output:phaseType:)`` still fires exactly once
  ///   at stream end with the final parsed ``TurnOutput``; consumers that
  ///   need canonical data (handlers, persistence) read from that event.
  case agentOutputStream(agent: String, primary: String?, thought: String?)

  // MARK: - Code Phase Results

  /// Scores have been updated (from `score_calc` phase).
  case scoreUpdate(scores: [String: Int])

  /// An agent has been eliminated (from `eliminate` phase).
  case elimination(agent: String, voteCount: Int)

  /// Data has been assigned to an agent (from `assign` phase).
  case assignment(agent: String, value: String)

  /// A summary text was generated (from `summarize` phase).
  case summary(text: String)

  // MARK: - Vote Results

  /// Vote results after a `vote` phase completes.
  /// `votes` maps voter name to voted-for name; `tallies` maps candidate to count.
  case voteResults(votes: [String: String], tallies: [String: Int])

  // MARK: - Pairing Results

  /// Result of a paired interaction in a `choose` phase with round-robin pairing.
  case pairingResult(agent1: String, action1: String, agent2: String, action2: String)

  // MARK: - Simulation Lifecycle

  /// The simulation has completed all rounds successfully.
  case simulationCompleted

  /// The simulation has been paused at the given position.
  case simulationPaused(round: Int, phaseIndex: Int)

  /// An error occurred during simulation execution.
  case error(SimulationError)

  // MARK: - Progress (UI Feedback)

  /// LLM inference has started for an agent. Used to show thinking indicators.
  case inferenceStarted(agent: String)

  /// LLM inference has completed for an agent with timing + optional token info.
  /// `tokenCount` is `nil` when the backend did not report completion tokens
  /// (e.g., Ollama without `usage` metadata). Consumers computing tok/s must
  /// treat nil as "unknown" rather than substituting zero.
  case inferenceCompleted(agent: String, durationSeconds: Double, tokenCount: Int?)
}

/// Errors that can occur during simulation execution.
///
/// Placed in Models alongside `SimulationEvent` because the event's `.error` case
/// references this type, and Models must have no external dependencies.
nonisolated public enum SimulationError: Error, Sendable, Equatable {
  /// The scenario definition failed validation (e.g., invalid phase type, too many agents).
  case scenarioValidationFailed(String)

  /// The LLM backend failed to generate a response.
  /// Stores the error description as a String for Sendable + Equatable conformance.
  case llmGenerationFailed(description: String)

  /// The LLM response could not be parsed as valid JSON.
  case jsonParseFailed(raw: String)

  /// All retry attempts for LLM inference were exhausted.
  case retriesExhausted

  /// The LLM model is not loaded. Call `loadModel()` before running.
  case modelNotLoaded

  /// The simulation was cancelled via Task cancellation.
  case cancelled
}

/// Provides human-readable descriptions so UI alert handlers can show
/// `error.localizedDescription` without mapping each case manually.
extension SimulationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .scenarioValidationFailed(let message):
      return message
    case .llmGenerationFailed(let description):
      return String(localized: "LLM generation failed: \(description)")
    case .jsonParseFailed(let raw):
      let snippet = raw.count > 200 ? String(raw.prefix(200)) + "..." : raw
      return String(localized: "JSON parse failed: \(snippet)")
    case .retriesExhausted:
      return String(
        localized: "LLM returned invalid output after retries. Try again or check model health.")
    case .modelNotLoaded:
      return String(localized: "Model not loaded")
    case .cancelled:
      return String(localized: "Simulation cancelled")
    }
  }
}
