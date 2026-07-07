import Foundation
import os

/// OSLog-backed ``EngineLogger`` — the only place in the app that turns Engine
/// diagnostics into `os.Logger` calls.
///
/// Lives in App/ (not Engine/) so the Engine stays free of `import os` for the
/// KMP migration (#501 S0.2), mirroring how `NLLanguageDetector` keeps
/// `NaturalLanguage` out of the Engine's `LanguageDetector` seam. Injected at
/// the `SimulationView` boundary (see `SimulationView.makeViewModel`).
///
/// `nonisolated` is load-bearing: under the app's default-MainActor isolation
/// this conforms to a `nonisolated` protocol whose `log` is called from
/// off-main Engine executors — a `.claude/rules/swift-isolation.md` Pattern 4
/// shape. Keep it stateless (a fresh `Logger` per call; `os.Logger` is cheap
/// and OSLog coalesces by subsystem+category) so no sync accessor ever forces
/// it back onto the MainActor.
nonisolated struct OSLogEngineLogger: EngineLogger {
  private static let subsystem = "app.pastura.Pastura"

  func log(
    _ level: EngineLogLevel,
    category: String,
    _ message: String,
    privacy: EngineLogPrivacy
  ) {
    let logger = Logger(subsystem: Self.subsystem, category: category)
    // The whole rendered message is one dynamic argument; `privacy` governs
    // whether it is shown or redacted off-device (TestFlight / Release),
    // preserving the pre-seam per-call OSLog privacy classification.
    switch (level, privacy) {
    case (.debug, .public): logger.debug("\(message, privacy: .public)")
    case (.debug, .private): logger.debug("\(message, privacy: .private)")
    case (.info, .public): logger.info("\(message, privacy: .public)")
    case (.info, .private): logger.info("\(message, privacy: .private)")
    case (.warning, .public): logger.warning("\(message, privacy: .public)")
    case (.warning, .private): logger.warning("\(message, privacy: .private)")
    }
  }
}
