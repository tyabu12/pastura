import Foundation
import PasturaSharedEngine

// `LanguageDetector` has a Swift twin in this module, so the Kotlin spelling is
// qualified `PasturaSharedEngine.LanguageDetector` — a bare name binds to the
// Swift protocol (`.claude/rules/kmp-interop.md` Pattern 1b). No typealias: an
// alias would hide the shadowing from the next reader.
//
// Measured against the staged ios-simulator slice 2026-08-31, the sole
// requirement exports as — verbatim header line:
//
//   - (NSString * _Nullable)detectText:(NSString *)text __attribute__((swift_name("detect(text:)")));
//
// so the nullable return arrives as `String?` and the Kotlin `null` skip value
// needs no translation, only forwarding.

/// Bridges Kotlin's `LanguageDetector` seam onto the app's Swift
/// ``LanguageDetector``, so the existing `NLLanguageDetector` is injected into
/// `SimulationEngine(detector:logger:random:)` unchanged (ADR-023 §5, S5-2
/// PR-B, #1647).
///
/// **Why it lives in `App/KMP/`.** ADR-023 §6 ruling (c) makes this directory
/// the permanent home of every K/N boundary adapter, and CLAUDE.md
/// § Dependency Rules makes it the only place `PasturaSharedEngine` may be
/// imported — `LLM/` must stay unaware of the umbrella (and, per ADR-010 D8,
/// free of `NaturalLanguage` besides). This file is §10-permanent: it does not
/// retire when the Kotlin port completes.
///
/// **Isolation.** `nonisolated` because Kotlin calls `detect` from
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
/// immutable `any LanguageDetector`, which the Swift protocol already refines
/// as `Sendable`, so a later `var` fails the build rather than quietly
/// re-opening a race.
nonisolated final class LanguageDetectorBridge: PasturaSharedEngine.LanguageDetector, Sendable {
  private let detector: any Pastura.LanguageDetector

  init(detector: any Pastura.LanguageDetector) {
    self.detector = detector
  }

  /// Forwards verbatim, `nil` included: Kotlin reads `null` as "skip the
  /// adherence check" exactly as `LLMCaller` does on the Swift side, so
  /// substituting a default here would turn a skip into a mismatch.
  func detect(text: String) -> String? {
    detector.detect(text: text)
  }
}
