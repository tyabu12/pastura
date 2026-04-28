import Foundation
import os

/// Wraps LLM inference calls with retry logic and event emission.
///
/// Retries up to 2 times on JSON parse failure or empty fields ("..." or "").
/// Emits `inferenceStarted` / `inferenceCompleted` events plus per-chunk
/// `agentOutputStream` snapshots for UI progress feedback.
///
/// Consumes the streaming ``LLMService/generateStream(system:user:schema:)`` path.
/// Backends that don't stream (MockLLMService without configured chunks,
/// OllamaService) yield a single terminal chunk via the protocol's default
/// wrap — this caller handles both shapes uniformly.
nonisolated struct LLMCaller: Sendable {

  private static let maxRetries = 2
  private let parser = JSONResponseParser()
  private let extractor = PartialOutputExtractor()
  private let logger = Logger(subsystem: "com.tyabu12.Pastura", category: "LLMCaller")
  // `category: "StreamingDiag"` matches the existing diagnostic channel
  // (PR #158) so `scripts/analyze-streaming-diag.sh` picks up the new
  // `repaired ...` lines alongside `retry ...` and `streamReset ...`.
  private let diagLogger = Logger(subsystem: "com.tyabu12.Pastura", category: "StreamingDiag")

  // swiftlint:disable function_parameter_count

  /// Calls the LLM with retry logic and returns a parsed ``TurnOutput``.
  ///
  /// - Parameters:
  ///   - llm: The LLM service to call.
  ///   - system: The system prompt.
  ///   - user: The user prompt.
  ///   - agentName: The agent's name (for event emission).
  ///   - schema: Optional ``OutputSchema`` for constrained decoding at
  ///     the backend (llama.cpp GBNF / Ollama format:json / Mock
  ///     capturedSchemas) AND the schema-aware repair guard in
  ///     ``JSONResponseParser/parse(_:expectedKeys:)`` — single source
  ///     of truth, derived once at the handler boundary. `nil` means
  ///     unconstrained generation + no repair guard.
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
    schema: OutputSchema? = nil,
    suspendController: SuspendController,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws -> TurnOutput {
    // Derive the parser-guard key set from the schema. This is the only
    // place `expectedKeys` is computed now; handlers pass `schema` once
    // and both the backend-layer constraint (grammar / format:json) and
    // the parser-layer repair guard flow from the same value (#194 PR#b
    // critic Axis 4 — drift-prone redundancy eliminated).
    let expectedKeys: Set<String> = Set(schema?.fields.map(\.name) ?? [])
    for attempt in 0...Self.maxRetries {
      emitter(.inferenceStarted(agent: agentName))
      let startTime = ContinuousClock.now

      let streamResult: StreamResult
      do {
        streamResult = try await consumeStreamWithSuspendRetry(
          llm: llm, system: system, user: user, schema: schema,
          controller: suspendController, agentName: agentName,
          emitter: emitter)
      } catch {
        let seconds = elapsedSeconds(since: startTime)
        // Tokens are unknown on failure — the backend didn't complete generation.
        emitter(
          .inferenceCompleted(
            agent: agentName, durationSeconds: seconds, tokenCount: nil))
        throw SimulationError.llmGenerationFailed(description: readableDescription(error))
      }

      let seconds = elapsedSeconds(since: startTime)
      // Retry inferences contribute to tok/s averages — this reflects real
      // device throughput (the "what did I observe" metric), not net-productive
      // throughput. Retries are rare in practice.
      emitter(
        .inferenceCompleted(
          agent: agentName, durationSeconds: seconds,
          tokenCount: streamResult.completionTokens))

      let raw = streamResult.rawText

      // Try to parse JSON, with optional A2 repair pipeline gated by the
      // schema-aware guard (#194 PR#a Item 2). On successful repair, emit
      // a `StreamingDiag` line so `scripts/analyze-streaming-diag.sh` can
      // bucket repair effects against pre-PR baselines.
      guard let parseResult = try? parser.parse(raw, expectedKeys: expectedKeys)
      else {
        logParseFailure(raw: raw, attempt: attempt)
        if attempt < Self.maxRetries {
          emitRetryCause(agent: agentName, attempt: attempt + 1, cause: "parse_failed")
          continue
        }
        throw SimulationError.retriesExhausted
      }
      let output = parseResult.0
      logRepairIfNeeded(agent: agentName, kind: parseResult.repairKind)
      logChatTemplateLeakage(in: raw)

      if hasEmptyFields(output) && attempt < Self.maxRetries {
        logEmptyFields(fields: output.fields, attempt: attempt)
        emitRetryCause(agent: agentName, attempt: attempt + 1, cause: "empty_field")
        continue
      }

      return output
    }

    // Should not reach here, but satisfy compiler
    throw SimulationError.retriesExhausted
  }

  // swiftlint:enable function_parameter_count

  /// Result of draining one stream successfully.
  private struct StreamResult {
    let rawText: String
    let completionTokens: Int?
  }

  /// Emit the parse-failure log lines (engineering channel + DEBUG
  /// console fallback). Extracted to keep `call` under the lint
  /// `function_body_length` budget.
  private func logParseFailure(raw: String, attempt: Int) {
    // `raw` may echo user-authored scenario / persona content via malformed
    // LLM output, but the same data is already persisted on-device to
    // `TurnRecord.rawOutput` (ADR-001), so OSLog exposure is consistent with
    // the existing surface. `.public` is required for diagnostic value in
    // TestFlight / Release builds.
    logger.warning(
      "JSON parse failed (attempt \(attempt + 1)/\(Self.maxRetries + 1)): raw=\(raw.prefix(500), privacy: .public)"
    )
    #if DEBUG
      // print() for reliable Xcode console visibility (os.Logger may be filtered)
      print(
        "[LLMCaller] JSON parse failed (attempt \(attempt + 1)/\(Self.maxRetries + 1)): raw=\(raw.prefix(500))"
      )
    #endif
  }

  /// Emit the `category:StreamingDiag` `retryCause` line consumed by
  /// `scripts/analyze-streaming-diag.sh`. Field order
  /// `agent=… attempt=… cause=…` is load-bearing — analyzer regex
  /// expects `cause=` to be the last token (#194 PR#a Item 4).
  private func emitRetryCause(agent: String, attempt: Int, cause: String) {
    diagLogger.info(
      "retryCause agent=\(agent, privacy: .public) attempt=\(attempt) cause=\(cause, privacy: .public)"
    )
  }

  /// Emit the `category:StreamingDiag` `repaired` line consumed by the
  /// analyzer. No-op when the parse didn't trip the repair pipeline.
  private func logRepairIfNeeded(agent: String, kind: String?) {
    guard let kind else { return }
    diagLogger.info(
      "repaired agent=\(agent, privacy: .public) kind=\(kind, privacy: .public)"
    )
  }

  /// Detect chat template token leakage and hallucinated continuations.
  /// `LlamaCppService`'s streaming path strips `<|im_end|>` before
  /// emission, so this primarily catches non-streaming backends (Mock
  /// wrap path, Ollama) where the raw string may still contain template
  /// tokens.
  private func logChatTemplateLeakage(in raw: String) {
    if raw.contains("<|im_start|>") {
      logger.warning(
        "Model hallucinated past its turn — continuation truncated at <|im_end|>")
    } else if raw.contains("<|im_end|>") {
      logger.debug("Trailing <|im_end|> token stripped from output")
    }
  }

  private func hasEmptyFields(_ output: TurnOutput) -> Bool {
    output.fields.values.contains { $0 == "..." || $0.isEmpty }
  }

  private func logEmptyFields(fields: [String: String], attempt: Int) {
    logger.debug(
      "Empty fields detected (attempt \(attempt + 1)/\(Self.maxRetries + 1)): fields=\(fields)"
    )
  }

  /// Drain one `generateStream` cycle, emitting per-snapshot UI events
  /// as chunks arrive. On ``LLMError/suspended``, awaits the controller's
  /// resume and re-issues the stream from scratch — same transparent
  /// retry behaviour the previous non-streaming implementation had for
  /// suspend cycles. On any other error, propagates.
  ///
  /// Each chunk's non-empty delta is accumulated, run through
  /// ``PartialOutputExtractor``, and emitted as an
  /// ``SimulationEvent/agentOutputStream(agent:primary:thought:)``.
  /// Consumers replace their per-agent buffer on each emission — a new
  /// stream (retry after parse failure, or re-issue after resume)
  /// naturally overwrites prior snapshots without a separate reset event.
  ///
  /// Handles both true streaming (LlamaCpp: many non-final chunks plus
  /// a final chunk carrying only tokens) and the wrap fallback (Mock
  /// wrap path / Ollama: one chunk with `isFinal=true` carrying the full
  /// text). In the wrap case, a single snapshot fires at the end — still
  /// consistent with the replacement semantics.
  private func consumeStreamWithSuspendRetry(  // swiftlint:disable:this function_parameter_count
    llm: LLMService,
    system: String,
    user: String,
    schema: OutputSchema?,
    controller: SuspendController,
    agentName: String,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws -> StreamResult {
    var suspendCount = 0
    while true {
      var rawText = ""
      var completionTokens: Int?
      let stream = llm.generateStream(system: system, user: user, schema: schema)
      do {
        for try await chunk in stream {
          if !chunk.delta.isEmpty {
            rawText += chunk.delta
            let snap = extractor.extract(from: rawText)
            emitter(
              .agentOutputStream(
                agent: agentName,
                primary: snap.primary,
                thought: snap.thought))
          }
          if chunk.isFinal {
            completionTokens = chunk.completionTokens
          }
        }
        return StreamResult(rawText: rawText, completionTokens: completionTokens)
      } catch LLMError.suspended {
        suspendCount += 1
        logger.info(
          "stream: caught .suspended (count=\(suspendCount)), awaiting resume")
        await controller.awaitResume()
        try Task.checkCancellation()
        // Loop: re-issue a fresh stream. Any partial snapshot emitted
        // before the suspend is naturally replaced by the new stream's
        // snapshots on the consumer side.
      }
    }
  }

  private func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
    let duration = ContinuousClock.now - start
    return Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
  }
}
