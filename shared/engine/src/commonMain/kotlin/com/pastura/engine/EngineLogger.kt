package com.pastura.engine

/**
 * Severity level for [EngineLogger] diagnostics.
 *
 * Deliberately minimal — only the subset the Engine actually emits
 * ([DEBUG] / [INFO] / [WARNING]) — so the platform logger maps it without
 * carrying unused OSLog levels. The Swift OSLog adapter maps these to the
 * matching `os.Logger` convenience calls (`warning` resolves to the `.error`
 * OSLog type, unchanged from the pre-seam code).
 *
 * Swift original: `Pastura/Pastura/Engine/EngineLogger.swift`.
 */
public enum class EngineLogLevel {
    DEBUG,
    INFO,
    WARNING,
}

/**
 * Whether a log message's content is shown or redacted in off-device
 * (TestFlight / Release) captures.
 *
 * Mirrors OSLog's redaction contract at message granularity: [PRIVATE] content
 * renders as `<private>` off-device, [PUBLIC] renders verbatim. The Engine
 * classifies each call site; the Swift OSLog adapter applies it.
 */
public enum class EngineLogPrivacy {
    PUBLIC,
    PRIVATE,
}

/**
 * Minimal logging seam that lets Engine code emit diagnostics without importing
 * OSLog directly.
 *
 * The concrete OSLog implementation (`OSLogEngineLogger`) stays in the Swift App
 * layer and is deliberately NOT ported, keeping the Engine free of `import os`
 * for the KMP migration (issue #501, Stage 0 / S0.2) — mirroring how the
 * `LanguageDetector` protocol keeps `NaturalLanguage` out of the Engine while
 * `NLLanguageDetector` lives in App/.
 *
 * The Engine builds the **fully-rendered message string** (preserving the exact
 * wire format that `scripts/analyze-streaming-diag.sh` parses) and passes the
 * OSLog `category` plus a privacy classification; the adapter maps `category` to
 * an `os.Logger(subsystem:category:)` and applies level + privacy. Callers must
 * NOT pre-redact — they pass the real content and let `privacy` govern
 * off-device exposure.
 *
 * **Injectable from the run path**: pass an implementation to
 * `SimulationEngine(logger = …)` and the runner threads it into every
 * [PhaseContext]; [NoopEngineLogger] is the default, so the Engine still emits
 * nothing unless a platform adapter is handed in.
 *
 * **A Swift conformer must be declared `nonisolated`.** K/N exports this as an
 * unannotated Obj-C protocol and [log] is called from `Dispatchers.Default`, so
 * a default-MainActor conformance compiles clean and traps at runtime — the
 * `LLMBackend` precedent, `.claude/rules/swift-isolation.md` Pattern 7.
 */
public interface EngineLogger {
    /**
     * Emit one diagnostic line.
     *
     * @param level Severity (maps to the matching OSLog level).
     * @param category OSLog category. Load-bearing — `"StreamingDiag"` is the
     *   channel `scripts/analyze-streaming-diag.sh` captures via
     *   `log stream --predicate '… AND category == "StreamingDiag"'`.
     * @param message The fully-rendered message. Not pre-redacted; [privacy]
     *   governs off-device exposure of the whole line.
     * @param privacy Whether [message] is shown or redacted in Release captures.
     */
    public fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy)
}

/**
 * A no-op [EngineLogger] used as the injection default so Engine unit tests and
 * non-App consumers (e.g. the ADR-013 headless harness, which reuses Engine but
 * not App) construct handlers without wiring OSLog. It is the default of both
 * `SimulationEngine(logger = …)` and [PhaseContext.logger]; production injects
 * `OSLogEngineLogger` at the Swift View boundary — see `SimulationView`.
 */
public class NoopEngineLogger : EngineLogger {
    override fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy) {}
}
