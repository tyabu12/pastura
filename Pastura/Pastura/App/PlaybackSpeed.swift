import Foundation

/// Playback speed tiers shared by the live simulation
/// (``SimulationViewModel``) and the DL-time demo replay
/// (``ReplayViewModel``). Pinned to four user-visible buckets:
/// `x0.5` / `x1` / `x1.5` / `Max`.
///
/// **Why public:** promoted from internal (was file-scoped in
/// `SimulationViewModel.swift` pre-#290) to public to fit
/// ``ReplayPlaybackConfig``'s public boundary. The enum's cases are
/// now part of the public API surface — adding or renaming a case is
/// SemVer-relevant per the CLAUDE.md "future SPM module extraction"
/// goal.
///
/// **Why `nonisolated`:** referenced by ``ReplayPlaybackConfig`` (a
/// `nonisolated public struct`); a MainActor-defaulted enum would
/// force the surrounding struct's `Sendable` conformance to break.
/// `SimulationViewModel` is `@MainActor` and consumes this type
/// freely — no isolation friction for value-type enums.
///
/// **Two consumers, two pacing models:**
/// - Sim uses ``charsPerSecond`` (typing animation) and
///   ``interEventDelayMs`` (non-agent inter-event delay).
/// - Replay uses ``multiplier`` to scale ``ReplayPlaybackConfig``'s
///   `turnDelayMs` / `codePhaseDelayMs`. ``.instant`` should be
///   handled by an explicit early-return at each delay-scaling
///   callsite (see ``ReplayViewModel.scaledDelay(for:)`` and
///   ``YAMLReplaySource``); the sentinel value below is provided
///   only so that arithmetic-only paths happen to compute zero, not
///   as the load-bearing way to get instant pacing.
nonisolated public enum PlaybackSpeed:
  String, CaseIterable, Identifiable, Sendable, Equatable {
  case slow
  case normal
  case fast
  case instant

  public var id: String { rawValue }

  /// Characters revealed per second during typing animation.
  /// `nil` means "render full text immediately" (`.instant`).
  /// Sim-only — replay does not animate typing.
  public var charsPerSecond: Double? {
    switch self {
    case .slow: 15
    case .normal: 30
    case .fast: 45
    case .instant: nil
    }
  }

  /// Delay inserted between consumed simulation events other than
  /// agent outputs (agent outputs are paced by the typing animation
  /// instead). Keeps round separators and phase labels on-screen long
  /// enough to read. Sim-only.
  public var interEventDelayMs: Int {
    switch self {
    case .slow, .normal, .fast: 120
    case .instant: 0
    }
  }

  /// Multiplier applied to ``ReplayPlaybackConfig``'s `turnDelayMs` /
  /// `codePhaseDelayMs` to derive the per-event sleep in
  /// ``ReplayViewModel.scaledDelay(for:)``. Replay-only.
  ///
  /// `.instant` returns `.infinity` so arithmetic paths (`base / multiplier`)
  /// happen to yield zero, but **do not rely on this** — every
  /// delay-scaling consumer should special-case `.instant` with an
  /// explicit early-return for symmetry and to avoid IEEE-754-dependent
  /// behavior. The sentinel exists for defense-in-depth.
  public var multiplier: Double {
    switch self {
    case .slow: 0.5
    case .normal: 1.0
    case .fast: 1.5
    case .instant: .infinity
    }
  }

  public var label: String {
    switch self {
    case .slow: "x0.5"
    case .normal: "x1"
    case .fast: "x1.5"
    case .instant: "Max"
    }
  }
}
