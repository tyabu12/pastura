import Foundation

/// UserDefaults-backed feature flags. Values are read on demand (no caching)
/// so a flipped flag takes effect on the next check without requiring a
/// relaunch.
///
/// Two flag policies coexist here. Pick the one that matches the flag's
/// purpose, and document the choice in the per-flag doc-comment:
///
/// - **Opt-out (default `true`)** — for stable-but-fragile features that
///   ship enabled, with the flag acting as a *rollback hatch*. Example:
///   ``realtimeStreamingEnabled``. See ADR-002 §10.
/// - **Opt-in (default `false`)** — for *unstable* features that need to
///   stay shipped (so developers can dogfood / verify) but must not be
///   exposed to TestFlight users until specific re-enable preconditions
///   are met. Example: ``backgroundContinuationEnabled``.
///
/// UserDefaults key names are **load-bearing across the eventual default
/// flip**. When the time comes to flip an opt-in flag's default to `true`
/// (re-enable preconditions met), keep the same key so that any
/// developer-side `defaults write` overrides remain honoured rather than
/// silently leaking under a renamed key.
nonisolated enum FeatureFlags {
  // MARK: - Keys

  private static let realtimeStreamingKey = "realtimeStreamingEnabled"
  private static let backgroundContinuationKey = "backgroundContinuationEnabled"

  // MARK: - Read accessors

  /// Whether the live token-by-token streaming path consumes
  /// ``SimulationEvent/agentOutputStream(agent:primary:thought:)`` events
  /// and renders a live streaming row in the simulation view. When
  /// `false`, the UI falls back to the pre-streaming behaviour:
  /// "thinking…" indicator followed by the committed agent row once
  /// `.agentOutput` arrives (via AgentOutputRow's own reveal animation).
  ///
  /// Opt-out flag — defaults to `true`. Disable via:
  /// ```
  /// defaults write com.tyabu12.Pastura realtimeStreamingEnabled -bool false
  /// ```
  static var realtimeStreamingEnabled: Bool {
    defaultsReadBool(key: realtimeStreamingKey, default: true)
  }

  /// Whether the in-simulation background-continuation toggle (moon icon)
  /// is exposed in the UI. Gates `SimulationViewModel.canEnableBackgroundContinuation`
  /// — a single chokepoint that all UI rendering and VM scheduling branches
  /// funnel through, so flipping this flag suppresses the entire BG
  /// continuation surface (no separate UI-layer gate needed).
  ///
  /// **Opt-in flag — defaults to `false`** (exposure-shrink for an unstable
  /// feature, the *opposite* of ``realtimeStreamingEnabled``'s rollback-hatch
  /// policy). Reasoning: real-device QA surfaced two failure modes whose
  /// fixes are tracked separately:
  ///
  /// - **#111** — Gemma 4 E2B Q4_K_M peaks at ~5 GB resident on iPhone 15 Pro
  ///   class hardware; tight-memory devices receive `didReceiveMemoryWarning`
  ///   under nominal foreground load, which BG continuation amplifies (CPU
  ///   mode keeps the model resident across the BG transition, increasing
  ///   OOM-kill risk).
  /// - **#135** — Backgrounding mid-generation with GPU + BG continuation
  ///   OFF leaves the Metal backend in an unrecoverable error state
  ///   (`backgroundExecutionNotPermitted` cascade); the in-flight turn is
  ///   lost.
  ///
  /// While #111 / #135 remain unfixed, the toggle stays hidden from
  /// TestFlight users. The underlying `BackgroundSimulationManager` /
  /// `enableBackgroundContinuation` code paths are kept intact so the
  /// feature can be exercised under `defaults write` for developer
  /// verification; `BackgroundSimulationManager.register()` at app launch
  /// is harmless on its own (it only installs a system handler — without
  /// `scheduleRequest()` being called via `enableBackgroundContinuation`,
  /// no task is ever submitted).
  ///
  /// Developer override:
  /// ```
  /// defaults write com.tyabu12.Pastura backgroundContinuationEnabled -bool true
  /// ```
  ///
  /// **Re-enable checklist** — do *not* flip this default to `true` until
  /// all three are satisfied:
  /// 1. #111 closed with a memory-budget regression test on 6–8 GB-RAM
  ///    devices.
  /// 2. #135 closed with a Metal-recovery integration test (rebuild backend
  ///    on FG return after BG-induced command-buffer rejection).
  /// 3. Manual on-device validation: 10-minute BG run on a 3 GB-RAM device
  ///    class (iPhone SE) without OOM, FG return without Metal decode
  ///    failure.
  ///
  /// See tracking issue #254 for the broader rationale.
  static var backgroundContinuationEnabled: Bool {
    defaultsReadBool(key: backgroundContinuationKey, default: false)
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
