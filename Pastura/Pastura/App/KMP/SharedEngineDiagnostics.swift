import Foundation
import PasturaSharedEngine

// Kotlin types with a Swift twin in this module are spelled
// `PasturaSharedEngine.X` — a bare name binds to the Swift twin
// (`.claude/rules/kmp-interop.md` Pattern 1b).

/// Diagnostics-only helpers behind the Settings > Diagnostics section
/// (ADR-023 §6 S5-4, #1681).
///
/// It lives here rather than next to the View because the
/// `PasturaSharedEngine` umbrella may only be imported from `App/`
/// (CLAUDE.md § Dependency Rules) — the View calls this and imports nothing
/// new.
///
/// Sunset: deleted at S5-5 together with the Diagnostics section it feeds.
nonisolated enum SharedEngineDiagnostics {

  /// One Kotlin-rendered `ScenarioValidationMessage`, obtained by provoking
  /// the Kotlin loader with deliberately malformed YAML.
  ///
  /// **This is the S5-4 acceptance surface for #1632's residual.** The
  /// `appleMain` `localizedFormat` actual resolves the Kotlin catalog key
  /// against `Bundle.main`, so on a `ja` device this must read the catalog's
  /// `ja` value for `Invalid YAML format` — 「無効な YAML 形式です」. An English
  /// string on a `ja` device means the actual fell back to the key, which is
  /// exactly the regression this row exists to make visible.
  ///
  /// The message is *provoked* rather than constructed because the header
  /// exports no `ScenarioValidationMessage.InvalidYAMLFormat` initializer to
  /// call from Swift (`.claude/rules/kmp-interop.md` Pattern 2 covers what
  /// does and does not construct) — the loader's own throw is the one path
  /// that yields a rendered message.
  ///
  /// Cached (`static let`): the value cannot change within a process, and
  /// the View reads it on every body evaluation of the section — a K/N
  /// loader construction, parse, `Throwable` (stack capture) and `NSError`
  /// bridge per render, on the MainActor, buys nothing after the first.
  static let cachedSampleRenderedMessage: String = sampleRenderedMessage()

  static func sampleRenderedMessage() -> String {
    do {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: "agents: [")
      // Unreachable with this input; a Kotlin change that made the loader
      // accept it would leave the row with a bare prefix on device, where no
      // test runs — so show a non-localized tell instead of an empty string.
      return "(loader accepted malformed YAML)"
    } catch {
      return SharedEngineRunner.renderedValidationMessage(for: error)
    }
  }
}
