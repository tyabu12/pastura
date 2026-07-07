import Foundation

/// Severity level for ``EngineLogger`` diagnostics.
///
/// Deliberately minimal — only the subset the Engine actually emits
/// (`debug` / `info` / `warning`) — so a future Kotlin port maps it to the
/// platform logger without carrying unused OSLog levels. The OSLog adapter
/// maps these to the matching `os.Logger` convenience calls (`warning`
/// resolves to the `.error` OSLog type, unchanged from the pre-seam code).
nonisolated public enum EngineLogLevel: Sendable {
  case debug
  case info
  case warning
}

/// Whether a log message's content is shown or redacted in off-device
/// (TestFlight / Release) captures.
///
/// Mirrors OSLog's redaction contract at message granularity: `.private`
/// content renders as `<private>` off-device, `.public` renders verbatim.
/// The Engine classifies each call site; the OSLog adapter applies it.
nonisolated public enum EngineLogPrivacy: Sendable {
  case `public`
  case `private`
}

/// Minimal logging seam that lets Engine code emit diagnostics without
/// importing OSLog directly.
///
/// The concrete OSLog implementation (`OSLogEngineLogger`) lives in the App
/// layer, keeping the Engine free of `import os` for the KMP migration
/// (issue #501, Stage 0 / S0.2) — mirroring how the `LanguageDetector`
/// protocol keeps `NaturalLanguage` out of the Engine while `NLLanguageDetector`
/// lives in App/.
///
/// The Engine builds the **fully-rendered message string** (preserving the
/// exact wire format that `scripts/analyze-streaming-diag.sh` parses) and
/// passes the OSLog `category` plus a privacy classification; the adapter
/// maps `category` to an `os.Logger(subsystem:category:)` and applies level
/// + privacy. Callers must NOT pre-redact — they pass the real content and
/// let `privacy` govern off-device exposure.
///
/// Conforms to `Sendable` because it is stored in the `Sendable`
/// ``PhaseContext`` and the `Sendable` ``LLMCaller``.
nonisolated public protocol EngineLogger: Sendable {
  /// Emit one diagnostic line.
  ///
  /// - Parameters:
  ///   - level: Severity (maps to the matching OSLog level).
  ///   - category: OSLog category. Load-bearing — `"StreamingDiag"` is the
  ///     channel `scripts/analyze-streaming-diag.sh` captures via
  ///     `log stream --predicate '… AND category == "StreamingDiag"'`.
  ///   - message: The fully-rendered message. Not pre-redacted; `privacy`
  ///     governs off-device exposure of the whole line.
  ///   - privacy: Whether `message` is shown or redacted in Release captures.
  func log(
    _ level: EngineLogLevel,
    category: String,
    _ message: String,
    privacy: EngineLogPrivacy
  )
}

/// A no-op ``EngineLogger`` used as the injection default so Engine unit
/// tests and non-App consumers (e.g. the ADR-013 headless harness, which
/// reuses Engine but not App) construct handlers without wiring OSLog.
/// Production injects ``OSLogEngineLogger`` at the View boundary — see
/// `SimulationView`.
nonisolated public struct NoopEngineLogger: EngineLogger {
  public init() {}
  public func log(
    _ level: EngineLogLevel,
    category: String,
    _ message: String,
    privacy: EngineLogPrivacy
  ) {}
}
