#if DEBUG
  import Foundation
  import os

  /// DEBUG-only capture of raw token-piece byte streams from
  /// `LlamaCppService.runGeneration`.
  ///
  /// Produces JSON fixtures (see ``LlamaCppTraceFixture``) that record the
  /// exact bytes llama.cpp emits per sampled token — including partial
  /// UTF-8 sequences that split across pieces. Downstream tests for the
  /// partial JSON extractor and the streaming `LLMCaller` consumer replay
  /// these fixtures byte-by-byte, so they must be byte-accurate.
  ///
  /// Gating: capture runs only when the `PASTURA_TRACE_LLM` environment
  /// variable is set to a non-empty value. Off by default so production
  /// inference never pays the extra `decodePieceRaw` + append cost.
  ///
  /// Output: one JSON file per `generate()` call in the app's Documents
  /// directory, named `llm-trace-<timestamp>-<uuid8>.json`. Pull via
  /// Xcode's Devices window or the Files app, move into
  /// `PasturaTests/LLM/` as a new factory in
  /// `LlamaCppTraceFixtures.swift`.
  ///
  /// - Important: This file compiles only in DEBUG builds. Nothing in
  ///   production (non-DEBUG) code paths may reference these types.
  nonisolated enum LlamaCppTraceCapture {
    static let envVarName = "PASTURA_TRACE_LLM"

    /// Whether capture is enabled for this process. Evaluated once per
    /// `runGeneration` call — toggling the env var mid-session won't take
    /// effect until the next generate.
    static var isEnabled: Bool {
      guard let value = ProcessInfo.processInfo.environment[envVarName] else {
        return false
      }
      return !value.isEmpty
    }
  }

  extension LlamaCppService {
    /// Per-inference buffer of captured pieces. The sequential-access
    /// contract (ADR-002 §6) guarantees at most one active collector per
    /// `LlamaCppService` at a time, so no lock is required.
    nonisolated final class TraceCollector {
      let system: String
      let user: String
      var pieces: [LlamaCppTraceFixture.Piece] = []

      init(system: String, user: String) {
        self.system = system
        self.user = user
      }

      func append(tokenId: Int, bytes: Data) {
        pieces.append(.init(tokenId: tokenId, bytes: bytes))
      }
    }

    /// Flush a completed trace to disk. Called from `runGeneration` at the
    /// end of a successful inference (normal exit, EOG, stop-sequence).
    /// Errors during write are logged but not surfaced — a failed trace
    /// must never break inference.
    func writeTrace(
      collector: TraceCollector,
      finalText: String,
      completionTokens: Int?
    ) {
      let fixture = LlamaCppTraceFixture(
        model: modelIdentifier,
        backend: backendIdentifier,
        system: collector.system,
        user: collector.user,
        pieces: collector.pieces,
        finalText: finalText,
        completionTokens: completionTokens,
        notes: "Captured via PASTURA_TRACE_LLM"
      )

      guard
        let docs = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask
        ).first
      else {
        logger.error("trace: could not resolve Documents directory")
        return
      }

      // Local formatter — writeTrace runs at most once per generate() so a
      // per-call allocation is cheap, and ISO8601DateFormatter is not
      // Sendable (can't live as a static).
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
      let timestamp = formatter.string(from: Date())
      let suffix = UUID().uuidString.prefix(8)
      let url = docs.appendingPathComponent(
        "llm-trace-\(timestamp)-\(suffix).json")

      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixture)
        try data.write(to: url, options: .atomic)
        logger.info(
          "trace: wrote \(collector.pieces.count) pieces to \(url.lastPathComponent, privacy: .public)"
        )
      } catch {
        logger.error(
          "trace: write failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

#endif
