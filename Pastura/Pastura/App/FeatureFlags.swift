import Foundation

/// UserDefaults-backed feature flags. Values are read on demand (no caching)
/// so a flipped flag takes effect on the next check without requiring a
/// relaunch.
///
/// Defaults prefer **opt-out** semantics: new streaming-feature flags are
/// `true` by default in development so the feature is exercised, and can
/// be toggled off via `defaults write` or a future settings toggle if it
/// proves fragile in TestFlight. Rollback via flag flip is the intended
/// safety hatch — see ADR-002 §10 for the streaming-extension context.
nonisolated enum FeatureFlags {
  // MARK: - Keys

  private static let realtimeStreamingKey = "realtimeStreamingEnabled"

  // MARK: - Read accessors

  /// Whether the live token-by-token streaming path consumes
  /// ``SimulationEvent/agentOutputStream(agent:primary:thought:)`` events
  /// and renders a live streaming row in the simulation view. When
  /// `false`, the UI falls back to the pre-streaming behaviour:
  /// "thinking…" indicator followed by the committed agent row once
  /// `.agentOutput` arrives (via AgentOutputRow's own reveal animation).
  ///
  /// Defaults to `true`. Disable via:
  /// ```
  /// defaults write com.pastura.Pastura realtimeStreamingEnabled -bool false
  /// ```
  static var realtimeStreamingEnabled: Bool {
    defaultsReadBool(key: realtimeStreamingKey, default: true)
  }

  // MARK: - Helpers

  /// Read a Bool with a default. `UserDefaults.bool(forKey:)` returns
  /// `false` for missing keys, which collapses "never set" with
  /// "explicitly set to false". Use `object(forKey:)` to distinguish.
  private static func defaultsReadBool(key: String, default fallback: Bool) -> Bool {
    guard let value = UserDefaults.standard.object(forKey: key) as? Bool else {
      return fallback
    }
    return value
  }
}
