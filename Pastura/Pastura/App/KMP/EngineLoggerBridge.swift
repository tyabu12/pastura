import Foundation
import PasturaSharedEngine

// `EngineLogger`, `EngineLogLevel`, `EngineLogPrivacy` and `NoopEngineLogger`
// all have Swift twins in this module, so every Kotlin spelling below is
// qualified `PasturaSharedEngine.X` — a bare name binds to the Swift twin
// (`.claude/rules/kmp-interop.md` Pattern 1b). No typealias: an alias would
// hide the shadowing from the next reader.
//
// Measured against the staged ios-simulator slice 2026-08-31, the two enums
// export as Obj-C singleton classes over `PSEKotlinEnum` — verbatim header
// lines:
//
//   @property (class, readonly) PSEEngineLogLevel *debug __attribute__((swift_name("debug")));
//   @property (class, readonly) PSEEngineLogLevel *info __attribute__((swift_name("info")));
//   @property (class, readonly) PSEEngineLogLevel *warning __attribute__((swift_name("warning")));
//   @property (class, readonly) PSEEngineLogPrivacy *public_ __attribute__((swift_name("public_")));
//   @property (class, readonly) PSEEngineLogPrivacy *private_ __attribute__((swift_name("private_")));
//
// `public` / `private` are Swift keywords, hence the Kotlin statics' trailing
// underscore. `PSEKotlinEnum` also exposes `name` and `ordinal`; identity is
// what this file maps on, because each static is the one singleton instance.
// The requirement itself exports as
// `log(level:category:message:privacy:)` — note the *labelled* first argument,
// unlike the Swift protocol's unlabelled one.

/// Bridges Kotlin's `EngineLogger` seam onto the app's Swift ``EngineLogger``,
/// so the existing `OSLogEngineLogger` is injected into
/// `SimulationEngine(detector:logger:random:)` unchanged (ADR-023 §5, S5-2
/// PR-B, #1647).
///
/// **Why it lives in `App/KMP/`.** ADR-023 §6 ruling (c) makes this directory
/// the permanent home of every K/N boundary adapter, and CLAUDE.md
/// § Dependency Rules makes it the only place `PasturaSharedEngine` may be
/// imported — `Engine/` must stay unaware of the umbrella. So the adapter, not
/// the logger, owns the translation. This file is §10-permanent: it does not
/// retire when the Kotlin port completes.
///
/// **Isolation.** `nonisolated` because Kotlin calls `log` from
/// `Dispatchers.Default` — stated by the interface's own KDoc in
/// `shared/engine`, not yet by the Pattern 7 probe against the staged
/// framework (S5-2 PR-C runs it). K/N exports the interface as an Obj-C
/// protocol that is expected to import unannotated, in which case a
/// default-MainActor conformer's `@objc` thunk carries a MainActor
/// precondition that compiles clean and traps at runtime
/// (`.claude/rules/swift-isolation.md` Pattern 7). `nonisolated` is the safe
/// direction whichever way the probe lands.
///
/// **Plain `Sendable`, not `@unchecked`.** The only stored member is an
/// immutable `any EngineLogger`, which the Swift protocol already refines as
/// `Sendable`, so a later `var` fails the build rather than quietly re-opening
/// a race.
nonisolated final class EngineLoggerBridge: PasturaSharedEngine.EngineLogger, Sendable {
  private let logger: any Pastura.EngineLogger

  init(logger: any Pastura.EngineLogger) {
    self.logger = logger
  }

  func log(
    level: PasturaSharedEngine.EngineLogLevel,
    category: String,
    message: String,
    privacy: PasturaSharedEngine.EngineLogPrivacy
  ) {
    logger.log(
      Self.level(from: level),
      category: category,
      message,
      privacy: Self.privacy(from: privacy))
  }

  /// A Kotlin enum is not switch-exhaustive from Swift — K/N exports it as an
  /// Obj-C class whose cases are class properties, so this can only be an
  /// identity chain against those singletons and the compiler cannot tell us
  /// when Kotlin gains a fourth level.
  static func level(from shared: PasturaSharedEngine.EngineLogLevel) -> Pastura.EngineLogLevel {
    if shared === PasturaSharedEngine.EngineLogLevel.debug {
      return .debug
    } else if shared === PasturaSharedEngine.EngineLogLevel.info {
      return .info
    } else if shared === PasturaSharedEngine.EngineLogLevel.warning {
      return .warning
    } else {
      // An unrecognised level means Kotlin added a case this build predates.
      // Escalate to `.warning` — the loudest level the Swift enum has — so the
      // drift shows up in a capture instead of being filtered out at `.debug`.
      return .warning
    }
  }

  /// Same non-exhaustiveness as ``level(from:)``, with the opposite bias on the
  /// fallback.
  static func privacy(
    from shared: PasturaSharedEngine.EngineLogPrivacy
  ) -> Pastura.EngineLogPrivacy {
    if shared === PasturaSharedEngine.EngineLogPrivacy.public_ {
      return .public
    } else if shared === PasturaSharedEngine.EngineLogPrivacy.private_ {
      return .private
    } else {
      // An unrecognised privacy means Kotlin added a case this build predates.
      // Redact rather than guess: a wrong `.public` would ship user content
      // into an off-device capture with no way to take it back, while a wrong
      // `.private` only costs a `<private>` in a diagnostic.
      return .private
    }
  }
}
