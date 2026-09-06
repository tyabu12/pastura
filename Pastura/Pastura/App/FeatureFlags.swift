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
///
/// The `defaults write` **domain** below is the running build's bundle ID, which
/// the Debug configuration suffixes so a dev build can be installed alongside the
/// App Store build — so a locally-run build reads `app.pastura.Pastura.dev`, and
/// writing the unsuffixed domain silently affects the other app instead.
nonisolated enum FeatureFlags {
  // MARK: - Keys

  private static let realtimeStreamingKey = "realtimeStreamingEnabled"
  private static let backgroundContinuationKey = "backgroundContinuationEnabled"
  private static let keepRunningOnLeaveKey = "keepRunningOnLeaveEnabled"
  private static let viewerPredictionKey = "viewerPredictionEnabled"

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
  /// defaults write app.pastura.Pastura realtimeStreamingEnabled -bool false
  /// ```
  /// (append `.dev` to the domain when targeting a locally-built Debug app —
  /// see the type-level note.)
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
  /// policy). Reasoning: real-device QA surfaced two failure modes:
  ///
  /// - **Memory / OOM** (#111) — Gemma 4 E2B Q4_K_M peaks at ~5 GB resident
  ///   on iPhone 15 Pro class hardware; tight-memory devices receive
  ///   `didReceiveMemoryWarning` under nominal foreground load, which BG
  ///   continuation amplifies (CPU mode keeps the model resident across the
  ///   BG transition, increasing OOM-kill risk).
  /// - **Metal-backend unrecoverable state** (#135) — backgrounding
  ///   mid-generation with GPU + BG continuation OFF leaves the Metal backend
  ///   in an unrecoverable error state (`backgroundExecutionNotPermitted`
  ///   cascade); the in-flight turn is lost.
  ///
  /// **Status: parked indefinitely.** #111 / #135 and the umbrella #254 are
  /// all closed, but **without** the qualifying re-enable fixes below — BG
  /// continuation is still unstable and there is **no re-enable currently
  /// scheduled**. Do *not* read the closed-issue state as "preconditions met,
  /// almost shippable": issue-closure here does **not** mean the re-enable bar
  /// is satisfied (the bar is the engineering state below, not an issue count).
  ///
  /// The toggle therefore stays hidden from TestFlight users. The underlying
  /// `BackgroundSimulationManager` / `enableBackgroundContinuation` code paths
  /// are kept intact so the feature can be exercised under `defaults write`
  /// for developer verification; `BackgroundSimulationManager.register()` at
  /// app launch is harmless on its own (it only installs a system handler —
  /// without `scheduleRequest()` being called via
  /// `enableBackgroundContinuation`, no task is ever submitted).
  ///
  /// Developer override:
  /// ```
  /// defaults write app.pastura.Pastura backgroundContinuationEnabled -bool true
  /// ```
  /// (append `.dev` to the domain when targeting a locally-built Debug app —
  /// see the type-level note.)
  ///
  /// **Re-enable bar** — flip this default to `true` only once *all three*
  /// engineering preconditions actually hold (independent of any issue's
  /// open/closed state):
  /// 1. A memory-budget regression test passes on 6–8 GB-RAM devices — the
  ///    OOM amplification above no longer reproduces.
  /// 2. A Metal-recovery integration test passes — the backend rebuilds on FG
  ///    return after a BG-induced command-buffer rejection.
  /// 3. Manual on-device validation: a 10-minute BG run on a 3 GB-RAM device
  ///    class (iPhone SE) without OOM, FG return without Metal decode failure.
  ///
  /// **Deferred BG enhancements** — revisit together if/when BG is re-enabled
  /// (no-action while parked):
  /// - *Auto-rearm on FG return* — after a real BG activation + FG return the
  ///   toggle disarms, so the user must re-tap the moon icon each cycle.
  ///   Whether to auto-rearm (simpler, but may surprise users who didn't mean
  ///   to re-enable) or stay one-shot (explicit, but tedious for routine long
  ///   runs) needs TestFlight feedback to decide — which can't arrive while
  ///   the feature is parked. Seam: the `didActivateBGTask` branch in
  ///   `SimulationViewModel+Background.swift`'s `handleScenePhaseForeground`.
  ///   (Retired #117 — folded here as no-action.)
  ///
  /// See #254 (gating umbrella) and #84 (BG-execution feature lineage) for the
  /// broader rationale.
  static var backgroundContinuationEnabled: Bool {
    defaultsReadBool(key: backgroundContinuationKey, default: false)
  }

  /// Whether leaving the simulation screen keeps the run alive (parked in
  /// memory) instead of pausing it, skipping the per-leave dialog (ADR-017
  /// Phase B, #682). When `false` (the default), leaving an in-flight run
  /// raises the three-button confirm dialog (Pause and leave / Leave & keep
  /// running / Stay); when `true`, leaving silently parks the run and the
  /// in-flight indicator surfaces it on other tabs.
  ///
  /// **Opt-in flag — defaults to `false`.** Unlike
  /// ``backgroundContinuationEnabled`` (a dev-only `defaults write` escape
  /// hatch), this one is **user-facing**: the Settings toggle writes it via
  /// ``setKeepRunningOnLeave(_:)``. `defaultsReadBool` distinguishes "never
  /// set" from "explicitly off" so the unset default is honoured.
  static var keepRunningOnLeaveEnabled: Bool {
    defaultsReadBool(key: keepRunningOnLeaveKey, default: false)
  }

  /// Whether the viewer-prediction sheet interrupts the first vote reveal to
  /// ask the viewer to predict the outcome ("who is the wolf?" / "who is #1?";
  /// #915). Gates the `SimulationViewModel` interception; when `false`, runs
  /// play straight through with no prediction and no DB writes.
  ///
  /// **Opt-out flag — defaults to `true`.** It is the headline
  /// experience-changer from the #906 interestingness umbrella, so it ships
  /// enabled for discoverability; the sheet is skippable and time-boxed, so
  /// "watch only" viewers are not obstructed. User-facing: the Settings toggle
  /// writes it via ``setViewerPredictionEnabled(_:)``.
  static var viewerPredictionEnabled: Bool {
    defaultsReadBool(key: viewerPredictionKey, default: true)
  }

  // MARK: - Write accessors

  /// Persists the user's choice for ``keepRunningOnLeaveEnabled`` (Settings
  /// toggle). Read on demand (no caching), so the next leave honours it.
  static func setKeepRunningOnLeave(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: keepRunningOnLeaveKey)
  }

  /// Persists the user's choice for ``viewerPredictionEnabled`` (Settings
  /// toggle). Read on demand (no caching), so the next run honours it.
  static func setViewerPredictionEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: viewerPredictionKey)
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
