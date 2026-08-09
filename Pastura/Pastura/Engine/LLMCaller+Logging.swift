import Foundation

// Log-emission helpers factored out of `LLMCaller` so the core file stays
// under SwiftLint's `file_length` budget (mirrors `LLMCaller+StreamFailure`).
// These build the fully-rendered message and route it through the injected
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

  /// Detect chat template token leakage and hallucinated continuations.
  /// `LlamaCppService`'s streaming path strips a spelled-out `<|im_end|>`
  /// before emission, so this primarily catches non-streaming backends (Mock
  /// wrap path, Ollama) where the raw string may still contain template
  /// tokens.
  ///
  /// - Important: ChatML-only. Gemma 4's markers are `<|turn>` / `<turn|>`, so
  ///   this diagnostic sees nothing for the default shipped model. Note the
  ///   backends named above are exactly the ones without llama.cpp's
  ///   decode-side guarantee, which is what makes them the residual surface
  ///   here. Making it model-aware is tracked in #1422.
  func logChatTemplateLeakage(in raw: String) {
    if raw.contains("<|im_start|>") {
      logger.log(
        .warning, category: Self.logCategory,
        "Model hallucinated past its turn — continuation truncated at <|im_end|>",
        privacy: .public)
    } else if raw.contains("<|im_end|>") {
      logger.log(
        .debug, category: Self.logCategory,
        "Trailing <|im_end|> token stripped from output", privacy: .public)
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
