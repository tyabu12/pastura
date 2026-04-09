import Foundation
import os

/// Wraps LLM inference calls with retry logic and event emission.
///
/// Retries up to 2 times on JSON parse failure or empty fields ("..." or "").
/// Emits `inferenceStarted`/`inferenceCompleted` events for UI progress feedback.
nonisolated struct LLMCaller: Sendable {

  private static let maxRetries = 2
  private let parser = JSONResponseParser()
  private let logger = Logger(subsystem: "com.pastura", category: "LLMCaller")

  /// Calls the LLM with retry logic and returns a parsed ``TurnOutput``.
  ///
  /// - Parameters:
  ///   - llm: The LLM service to call.
  ///   - system: The system prompt.
  ///   - user: The user prompt.
  ///   - agentName: The agent's name (for event emission).
  ///   - emitter: Closure to emit simulation events.
  /// - Returns: A parsed ``TurnOutput`` with all fields populated.
  /// - Throws: ``SimulationError/retriesExhausted`` after max retries,
  ///           ``SimulationError/llmGenerationFailed(description:)`` on LLM errors.
  func call(
    llm: LLMService,
    system: String,
    user: String,
    agentName: String,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws -> TurnOutput {
    for attempt in 0...Self.maxRetries {
      emitter(.inferenceStarted(agent: agentName))
      let startTime = ContinuousClock.now

      let raw: String
      do {
        raw = try await llm.generate(system: system, user: user)
      } catch {
        let duration = ContinuousClock.now - startTime
        let seconds =
          Double(duration.components.seconds)
          + Double(duration.components.attoseconds) / 1e18
        emitter(.inferenceCompleted(agent: agentName, durationSeconds: seconds))
        throw SimulationError.llmGenerationFailed(description: "\(error)")
      }

      let duration = ContinuousClock.now - startTime
      let seconds =
        Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18
      emitter(.inferenceCompleted(agent: agentName, durationSeconds: seconds))

      // Try to parse JSON
      guard let output = try? parser.parse(raw) else {
        logger.warning(
          "JSON parse failed (attempt \(attempt + 1)/\(Self.maxRetries + 1)): raw=\(raw.prefix(500))"
        )
        #if DEBUG
          // print() for reliable Xcode console visibility (os.Logger may be filtered)
          print(
            "[LLMCaller] JSON parse failed (attempt \(attempt + 1)/\(Self.maxRetries + 1)): raw=\(raw.prefix(500))"
          )
        #endif
        if attempt < Self.maxRetries { continue }
        throw SimulationError.retriesExhausted
      }

      // Detect chat template token leakage and hallucinated continuations
      // TODO: Move this detection into JSONResponseParser as returned metadata
      // to avoid duplicating <|im_end|>/<|im_start|> knowledge across files.
      if raw.contains("<|im_start|>") {
        // Model generated past its own turn into fabricated user/assistant exchanges
        logger.warning("Model hallucinated past its turn — continuation truncated at <|im_end|>")
      } else if raw.contains("<|im_end|>") {
        // End-of-turn token leaked into output (llama_vocab_is_eog missed it)
        logger.debug("Trailing <|im_end|> token stripped from output")
      }

      // Check for empty fields ("..." or "")
      let hasEmpty = output.fields.values.contains { $0 == "..." || $0.isEmpty }
      if hasEmpty && attempt < Self.maxRetries {
        logger.debug(
          "Empty fields detected (attempt \(attempt + 1)/\(Self.maxRetries + 1)): fields=\(output.fields)"
        )
        continue
      }

      return output
    }

    // Should not reach here, but satisfy compiler
    throw SimulationError.retriesExhausted
  }
}
