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

  // swiftlint:disable function_parameter_count

  /// Calls the LLM with retry logic and returns a parsed ``TurnOutput``.
  ///
  /// - Parameters:
  ///   - llm: The LLM service to call.
  ///   - system: The system prompt.
  ///   - user: The user prompt.
  ///   - agentName: The agent's name (for event emission).
  ///   - suspendController: Controller used to coordinate cooperative suspend
  ///     with the LLM layer. When the LLM throws ``LLMError/suspended``, this
  ///     method awaits ``SuspendController/awaitResume()`` and retries the
  ///     same prompt without consuming the parse-error retry budget.
  ///   - emitter: Closure to emit simulation events.
  /// - Returns: A parsed ``TurnOutput`` with all fields populated.
  /// - Throws: ``SimulationError/retriesExhausted`` after max retries,
  ///           ``SimulationError/llmGenerationFailed(description:)`` on LLM errors.
  func call(
    llm: LLMService,
    system: String,
    user: String,
    agentName: String,
    suspendController: SuspendController,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws -> TurnOutput {
    for attempt in 0...Self.maxRetries {
      emitter(.inferenceStarted(agent: agentName))
      let startTime = ContinuousClock.now

      let raw: String
      do {
        raw = try await generateWithSuspendRetry(
          llm: llm, system: system, user: user, controller: suspendController
        )
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

  // swiftlint:enable function_parameter_count

  /// Wraps `llm.generate` to convert ``LLMError/suspended`` into a transparent
  /// re-issue of the same prompt after the controller resumes.
  ///
  /// Suspend cycles are invisible to the parse-retry loop above and to the UI
  /// (no extra `inferenceStarted`/`inferenceCompleted` pair is emitted), so
  /// users who background and foreground the app multiple times during one
  /// inference still see a single "thinking..." indicator until the inference
  /// either succeeds or fails for a non-suspend reason.
  ///
  /// `Task.checkCancellation()` after `awaitResume()` ensures the calling task
  /// can still be cancelled (e.g., user explicitly stops the simulation while
  /// the controller is suspended).
  private func generateWithSuspendRetry(
    llm: LLMService,
    system: String,
    user: String,
    controller: SuspendController
  ) async throws -> String {
    var attempt = 0
    while true {
      attempt += 1
      logger.info("generateWithSuspendRetry: attempt #\(attempt) — calling llm.generate")
      do {
        let result = try await llm.generate(system: system, user: user)
        logger.info("generateWithSuspendRetry: attempt #\(attempt) — generate returned ok")
        return result
      } catch LLMError.suspended {
        logger.info(
          "generateWithSuspendRetry: attempt #\(attempt) — caught .suspended, awaiting resume"
        )
        await controller.awaitResume()
        logger.info(
          "generateWithSuspendRetry: attempt #\(attempt) — resumed, re-checking cancellation")
        try Task.checkCancellation()
      } catch {
        logger.error(
          "generateWithSuspendRetry: attempt #\(attempt) — generate threw non-suspend error: \(error.localizedDescription, privacy: .public)"
        )
        throw error
      }
    }
  }
}
