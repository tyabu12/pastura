import Foundation

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

  // `internal` so the sibling `LLMCaller+StreamFailure` extension can read it.
  static let maxRetries = 2
  private let parser = JSONResponseParser()
  private let extractor = PartialOutputExtractor()

  /// Injected logging seam. Replaces the former two `os.Logger` instances so
  /// the Engine no longer imports OSLog (#501 S0.2); the OSLog implementation
  /// lives in App/ (`OSLogEngineLogger`). Handlers construct
  /// `LLMCaller(logger: context.logger)`. `internal` (not `private`) so the
  /// sibling `LLMCaller+Logging` extension can read it.
  let logger: any EngineLogger

  /// OSLog category for general LLMCaller diagnostics. `internal` so the
  /// sibling `LLMCaller+Logging` extension can read it.
  static let logCategory = "LLMCaller"
  /// OSLog category for the streaming-diagnostic channel that
  /// `scripts/analyze-streaming-diag.sh` captures (`retryCause` / `repaired` /
  /// `langCheckSkipped`). Load-bearing — must stay `"StreamingDiag"`.
  static let diagCategory = "StreamingDiag"

  /// - Parameter logger: The logging seam. Defaults to ``NoopEngineLogger``
  ///   (silent) so tests / non-App consumers construct `LLMCaller()`;
  ///   production handlers pass `context.logger`.
  init(logger: any EngineLogger = NoopEngineLogger()) {
    self.logger = logger
  }

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
  ///   - detector: Optional ``LanguageDetector`` for ADR-010 Step E PR2
  ///     output-language adherence enforcement. When both `detector`
  ///     and `expectedLanguage` are non-nil, a post-parse adherence
  ///     check runs after the empty-field check; on mismatch within the
  ///     existing ``maxRetries`` budget the call retries (`retryCause
  ///     cause=language_mismatch`), and on exhaustion a
  ///     ``SimulationEvent/languageMismatch(agent:detected:expected:)``
  ///     is emitted and the parsed output is still returned (sim
  ///     continues — structurally distinct from `parse_failed` /
  ///     `empty_field` exhaustion which throws).
  ///   - expectedLanguage: The scenario's `engineLanguage` per ADR-010
  ///     D5/D6. `nil` skips the adherence check entirely (back-compat
  ///     for callers that pre-date Step E PR2).
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
    detector: (any LanguageDetector)? = nil,
    expectedLanguage: String? = nil,
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
        // Tokens are unknown on failure — the backend didn't complete generation.
        emitInferenceCompleted(agent: agentName, since: startTime, tokens: nil, emitter: emitter)
        // The generation loops intercept the common sampler-crash case as
        // end-of-generation (#907); this retry is defense in depth (#885).
        // Other throws abort. See `shouldRetryStreamFailure`.
        if shouldRetryStreamFailure(error, agent: agentName, attempt: attempt) {
          continue
        }
        throw SimulationError.llmGenerationFailed(description: readableDescription(error))
      }

      // Retry inferences contribute to tok/s averages — this reflects real
      // device throughput (the "what did I observe" metric), not net-productive
      // throughput. Retries are rare in practice.
      emitInferenceCompleted(
        agent: agentName, since: startTime,
        tokens: streamResult.completionTokens, emitter: emitter)

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

      // Language adherence check (ADR-010 Step E PR2). Ordered after
      // parse_failed + empty_field — shape failures take priority
      // because a wrong-language-but-empty-field response should retry
      // for the empty field first. The check no-ops when detector or
      // expectedLanguage is nil (back-compat path) and when the joined
      // natural-language input is below the min-length gate. See
      // `handleLanguageAdherence` for the side-effect contract.
      if handleLanguageAdherence(
        output: output, schema: schema,
        detector: detector, expectedLanguage: expectedLanguage,
        agentName: agentName, attempt: attempt, emitter: emitter) {
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

  // Log-emission helpers (`logParseFailure`, `emitRetryCause`,
  // `logRepairIfNeeded`, `logChatTemplateLeakage`, `logEmptyFields`,
  // `emitLangCheckSkipped`) live in `LLMCaller+Logging.swift` to keep this
  // file under SwiftLint's `file_length` budget.

  private func hasEmptyFields(_ output: TurnOutput) -> Bool {
    output.fields.values.contains { $0 == "..." || $0.isEmpty }
  }

  // MARK: - Language Adherence (ADR-010 Step E PR2)

  /// Minimum codepoint count of joined natural-language values required
  /// to run the adherence check. `NLLanguageRecognizer` confidence drops
  /// sharply on short inputs (single proper nouns, enum tokens) — below
  /// the gate we skip rather than spuriously flag a "mismatch" on text
  /// that wasn't really natural language to begin with. Initial value
  /// per critic pass 2; benchmark in item 6 records skip-rate so the
  /// number can be revisited in a follow-up if needed.
  private static let minDetectionLength = 12

  /// Decide whether the current attempt's parsed output triggers a
  /// language-adherence retry, and apply the side effects (emit retry
  /// cause or emit `.languageMismatch` on exhaustion). Extracted from
  /// `call()` so the loop body stays under the `function_body_length`
  /// budget.
  ///
  /// - Returns: `true` when the caller should `continue` the loop
  ///   (retry the inference). `false` when the caller should proceed
  ///   to `return output` — either because no mismatch was detected,
  ///   or because the retry budget was exhausted and the event has
  ///   already been emitted (sim continues with the parsed output).
  private func handleLanguageAdherence(  // swiftlint:disable:this function_parameter_count
    output: TurnOutput, schema: OutputSchema?,
    detector: (any LanguageDetector)?, expectedLanguage: String?,
    agentName: String, attempt: Int,
    emitter: @Sendable (SimulationEvent) -> Void
  ) -> Bool {
    guard
      let detected = detectLanguageMismatch(
        output: output, schema: schema,
        detector: detector, expectedLanguage: expectedLanguage,
        agentName: agentName)
    else { return false }
    if attempt < Self.maxRetries {
      emitRetryCause(agent: agentName, attempt: attempt + 1, cause: "language_mismatch")
      return true
    }
    // Exhausted: surface the verdict but fall through. expectedLanguage
    // is non-nil here because detectLanguageMismatch only returns
    // non-nil when both detector and expectedLanguage are set.
    if let expected = expectedLanguage {
      emitter(.languageMismatch(agent: agentName, detected: detected, expected: expected))
    }
    return false
  }

  /// Run the post-parse adherence check.
  ///
  /// - Returns: The detected language code when a mismatch was found
  ///   (caller uses this to seed the `.languageMismatch` event on
  ///   exhaustion). Returns `nil` when the check was skipped or the
  ///   output matches the expected language — both cases mean "no
  ///   retry needed".
  private func detectLanguageMismatch(
    output: TurnOutput, schema: OutputSchema?,
    detector: (any LanguageDetector)?, expectedLanguage: String?,
    agentName: String
  ) -> String? {
    guard let detector, let expected = expectedLanguage else { return nil }
    let values = naturalLanguageFieldValues(output: output, schema: schema)
    let joined = values.joined(separator: "\n")
    if joined.unicodeScalars.count < Self.minDetectionLength {
      emitLangCheckSkipped(agent: agentName, reason: "too_short")
      return nil
    }
    guard let detected = detector.detect(text: joined) else { return nil }
    return detected == expected ? nil : detected
  }

  /// Collect natural-language values from `output`, keeping only fields
  /// whose `kind == .string`. Author-defined choice tokens
  /// (`kind == .choice`, e.g. `cooperate` / `betray` in a `choose`
  /// phase) are excluded — their language is fixed by the scenario
  /// author, not the LLM, so they would skew the detector's verdict
  /// (ADR-010 Step E, #405). The `.string`-only whitelist excludes
  /// `.choice` by construction.
  ///
  /// When `schema` is nil the caller hasn't opted into constrained
  /// decoding; we treat every field as natural language (conservative
  /// fallback — unconstrained generation is rare in the production
  /// path).
  private func naturalLanguageFieldValues(
    output: TurnOutput, schema: OutputSchema?
  ) -> [String] {
    guard let schema else { return Array(output.fields.values) }
    let naturalNames = Set(
      schema.fields.compactMap { field -> String? in
        if case .string = field.kind { return field.name }
        return nil
      })
    return output.fields.compactMap { key, value in
      naturalNames.contains(key) ? value : nil
    }
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
    // Surface the phase's private-thought field in the live snapshot: vote
    // streams `reason`, speak/choose stream `inner_thought`. Derived from the
    // schema so the streaming THINKING section matches the committed-display
    // resolver (`TurnOutput.secondaryText(for:)`) — see #609.
    let thoughtKey = schema?.thoughtFieldName ?? PartialOutputExtractor.thoughtKey
    while true {
      var rawText = ""
      var completionTokens: Int?
      let stream = llm.generateStream(system: system, user: user, schema: schema)
      do {
        for try await chunk in stream {
          if !chunk.delta.isEmpty {
            rawText += chunk.delta
            let snap = extractor.extract(from: rawText, thoughtKey: thoughtKey)
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
        logger.log(
          .info, category: Self.logCategory,
          "stream: caught .suspended (count=\(suspendCount)), awaiting resume",
          privacy: .public)
        await controller.awaitResume()
        try Task.checkCancellation()
        // Loop: re-issue a fresh stream. Any partial snapshot emitted
        // before the suspend is naturally replaced by the new stream's
        // snapshots on the consumer side.
      }
    }
  }

}
