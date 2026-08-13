import Foundation

// Diagnostics helpers factored out of `LLMCaller` so the core file stays
// under SwiftLint's `file_length` budget (mirrors `LLMCaller+StreamFailure`).
// Mostly log emission, but `parseAndLog` also *parses* and returns a
// `TurnOutput` — it lives here because the turn-marker set has to be read once
// and shared with `logChatTemplateLeakage`.
// The log-emitting members build the fully-rendered message and route it through the injected
// ``EngineLogger`` seam (#501 S0.2) — the OSLog `category`, message wire
// format, level, and privacy are preserved so `scripts/analyze-streaming-diag.sh`
// keeps parsing the same lines.
//
// `nonisolated` on the extension is required because `LLMCaller` is a
// `nonisolated` Engine type split across sibling files (a plain `extension`
// would inherit MainActor under the project's default-actor isolation and
// break the nonisolated callers in `call`).
nonisolated extension LLMCaller {
  /// Emit the parse-failure log lines (engineering channel + DEBUG
  /// console fallback). Extracted to keep `call` under the lint
  /// `function_body_length` budget.
  /// - Note: `agent=` is load-bearing for the harness's stderr diagnostics
  ///   channel: the terminal failure of a turn does NOT emit a following
  ///   `retryCause` line (`call` throws instead), so a reader cannot recover
  ///   the agent by scanning neighbours — the record has to name itself.
  ///   `raw=` stays the trailing token because it is unbounded and multi-line.
  func logParseFailure(agent: String, raw: String, attempt: Int) {
    // `raw` may echo user-authored scenario / persona content via malformed
    // LLM output, but the same data is already persisted on-device to
    // `TurnRecord.rawOutput` (ADR-001), so OSLog exposure is consistent with
    // the existing surface. `.public` is required for diagnostic value in
    // TestFlight / Release builds.
    logger.log(
      .warning, category: Self.logCategory,
      "JSON parse failed agent=\(agent) (attempt \(attempt + 1)/\(Self.maxRetries + 1)): raw=\(raw.prefix(500))",
      privacy: .public
    )
    #if DEBUG
      // print() for reliable Xcode console visibility (os.Logger may be filtered)
      print(
        "[LLMCaller] JSON parse failed agent=\(agent) (attempt \(attempt + 1)/\(Self.maxRetries + 1)): raw=\(raw.prefix(500))"
      )
    #endif
  }

  /// Emit the `category:StreamingDiag` `retryCause` line consumed by
  /// `scripts/analyze-streaming-diag.sh`. Field order
  /// `agent=… attempt=… cause=…` is load-bearing — analyzer regex
  /// expects `cause=` to be the last token (#194 PR#a Item 4).
  ///
  /// Non-`private` so the sibling `LLMCaller+StreamFailure` extension can
  /// emit the `sampler_crash` cause (#885).
  func emitRetryCause(agent: String, attempt: Int, cause: String) {
    logger.log(
      .info, category: Self.diagCategory,
      "retryCause agent=\(agent) attempt=\(attempt) cause=\(cause)",
      privacy: .public
    )
  }

  /// Emit the `category:StreamingDiag` `repaired` line consumed by the
  /// analyzer. No-op when the parse didn't trip the repair pipeline.
  func logRepairIfNeeded(agent: String, kind: String?) {
    guard let kind else { return }
    logger.log(
      .info, category: Self.diagCategory,
      "repaired agent=\(agent) kind=\(kind)",
      privacy: .public
    )
  }

  /// Parse `raw` with the backend's own turn markers, and emit the two
  /// diagnostics that belong to a *successful* parse.
  ///
  /// Extracted from `call` so that body stays under the 50-line
  /// `function_body_length` cap, and so the marker set is read once and used
  /// by both consumers — the parser and the leakage diagnostic — with no way
  /// for them to drift onto different sets.
  ///
  /// `knownTurnMarkers` is read from the live backend, so truncation keys on
  /// the loaded model's own sentinels (#1422). The read goes through
  /// `any LLMService`, which is exactly why that requirement is declared in
  /// the protocol body rather than an extension — see its doc comment.
  ///
  /// - Returns: the parsed output, or `nil` when the parse failed (the caller
  ///   owns the retry / `retriesExhausted` decision).
  func parseAndLog(
    raw: String, expectedKeys: Set<String>, llm: any LLMService, agent: String
  ) -> TurnOutput? {
    let markers = llm.knownTurnMarkers
    guard
      let result = try? parser.parse(
        raw, expectedKeys: expectedKeys, turnMarkers: markers)
    else { return nil }
    logRepairIfNeeded(agent: agent, kind: result.repairKind)
    logChatTemplateLeakage(in: raw, markers: markers)
    return result.0
  }

  /// Detect chat template token leakage and hallucinated continuations,
  /// against the loaded model's own markers rather than a ChatML literal
  /// (#1422 — before that, this was silently blind for Gemma 4, the default
  /// shipped model).
  ///
  /// `LlamaCppService`'s streaming path strips a spelled-out `stopSequence`
  /// before emission, so this primarily catches non-streaming backends (Mock
  /// wrap path, Ollama) where the raw string may still contain template
  /// tokens. A spelled-out **start** marker stays reachable even under
  /// llama.cpp, whose streaming path strips `stopSequence` alone — that is
  /// what the #65 TODO on `LlamaCppService.stopSequence` is about.
  ///
  /// Severity split is preserved from the pre-#1422 shape: a start marker is
  /// the more suspicious of the two (`.warning`), a lone end marker is the
  /// ordinary trailing-sentinel case (`.debug`). Suspicion, not a verdict —
  /// this predicate is a bare substring test and cannot tell a fabricated next
  /// turn from a header echo or from marker text inside a string value.
  ///
  /// - Parameters:
  ///   - raw: The backend's raw text, before parsing.
  ///   - markers: `LLMService.knownTurnMarkers` for the backend that produced
  ///     `raw`.
  func logChatTemplateLeakage(in raw: String, markers: [ChatTurnMarkers]) {
    // Both `first(where:)` calls pick the first marker in **array order**, not
    // the one occurring earliest in `raw`. Only one line is emitted either
    // way, so with a multi-pair set the reported marker is set-order
    // arbitrary — read the line as "some marker is present", never as "this
    // one came first".
    if let marker = markers.first(where: { !$0.start.isEmpty && raw.contains($0.start) }) {
      // The message states presence only, with no claim about what the model
      // did or what the parser then did. `raw.contains` is a plain substring
      // test, so it also fires on a leading template-header echo (which the
      // parser's start arm deliberately leaves in place) and on a marker
      // spelled inside a JSON string value (fixture:
      // `JSONResponseParserTests+TurnMarkers.startMarker_insideStringValue…`).
      // Neither is the model writing past its turn.
      logger.log(
        .warning, category: Self.logCategory,
        "Turn-start marker \(marker.start) present in raw output",
        privacy: .public)
    } else if let marker = markers.first(where: { !$0.end.isEmpty && raw.contains($0.end) }) {
      logger.log(
        .debug, category: Self.logCategory,
        "Trailing \(marker.end) token stripped from output", privacy: .public)
    }
  }

  /// Emit the empty-fields `.debug` diagnostic.
  ///
  /// `.private`: `fields` carries agent output. The former `os.Logger`
  /// interpolated it without `.public`, so OSLog redacted it as `<private>`
  /// off-device. The seam applies privacy per-message, so the whole `.debug`
  /// line is `.private` — a `.debug` line isn't persisted in Release anyway,
  /// and this errs toward more redaction, never less (#501 S0.2 documented
  /// delta: the static prefix, previously public, is also redacted off-device).
  func logEmptyFields(fields: [String: String], attempt: Int) {
    logger.log(
      .debug, category: Self.logCategory,
      "Empty fields detected (attempt \(attempt + 1)/\(Self.maxRetries + 1)): fields=\(fields)",
      privacy: .private
    )
  }

  /// Emit a `category:StreamingDiag` `langCheckSkipped` line. Field
  /// order `agent=… reason=…` matches the existing `retryCause` /
  /// `repaired` conventions (agent first; trailing key is the cause
  /// classification). Consumed by `scripts/analyze-streaming-diag.sh`.
  func emitLangCheckSkipped(agent: String, reason: String) {
    logger.log(
      .info, category: Self.diagCategory,
      "langCheckSkipped agent=\(agent) reason=\(reason)",
      privacy: .public
    )
  }
}
