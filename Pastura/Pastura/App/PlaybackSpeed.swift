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
/// **Consumers — properties are NOT universally consumed:**
/// - **Sim** (``SimulationViewModel``) uses ``charsPerSecond`` (typing
///   animation) and ``interEventDelayMs`` (non-agent inter-event delay).
/// - **``ReplayViewModel``** (the replay *pacing* model) uses
///   ``multiplier`` to scale ``ReplayPlaybackConfig``'s `turnDelayMs` /
///   `codePhaseDelayMs`. It does **not** consume ``charsPerSecond`` (it
///   advances bubbles on its own sleep clock, not a per-character
///   timeline) nor ``interEventDelayMs`` (its turn vs. codePhase
///   distinction is richer than Sim's flat 120ms-or-zero gap). Don't
///   extend replay pacing through the Sim-side properties; add a
///   replay-side property here if a new pacing dimension is needed.
/// - **The DL-time demo replay _screen_** (``ModelDownloadHostView``)
///   renders ``ReplayViewModel``'s `chatItems` through ``AgentOutputRow``.
///   Its typing cps comes from ``ReplayViewModel/typingCharsPerSecond``,
///   which (since #791) tracks the runtime ``ReplayViewModel/playbackSpeed``
///   — so the demo's Speed picker scales **both** typing cps (this property)
///   and turn dwell (``multiplier``), matching Sim at every speed (not just
///   x1). ``ReplayPlaybackConfig/typingCharsPerSecond`` remains the opt-in
///   gate (demo non-nil vs non-demo nil).
/// - ``.instant`` should be handled by an explicit early-return at
///   each delay-scaling callsite (see ``ReplayViewModel/scaledDelay(for:)``
///   and ``YAMLReplaySource``); the sentinel ``multiplier`` value is
///   provided only so that arithmetic-only paths happen to compute
///   zero, not as the load-bearing way to get instant pacing.
nonisolated public enum PlaybackSpeed:
  String, CaseIterable, Identifiable, Sendable, Equatable {
  case slow
  case normal
  case fast
  case instant

  public var id: String { rawValue }

  /// Characters revealed per second during typing animation.
  /// `nil` means "render full text immediately" (`.instant`).
  /// Consumed by Sim (``SimulationViewModel/effectiveCharsPerSecond(forEntryId:)``)
  /// and — since #791, via ``ReplayViewModel/typingCharsPerSecond`` keyed on
  /// the runtime ``ReplayViewModel/playbackSpeed`` — by the DL-time demo
  /// replay screen. ``ReplayViewModel``'s turn-dwell floor
  /// (``ReplayViewModel/typingFloorMs(for:)``) does NOT read this; it uses the
  /// fixed `config` reference, then ``ReplayViewModel/scaledDelay(for:floorMs:)``
  /// divides by ``multiplier`` (and `charsPerSecond == 30 × multiplier`, so the
  /// dwell stays synced with the speed-scaled typing).
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

  /// Reading pause held AFTER an agent utterance has fully revealed, before
  /// the next simulation event is consumed — the visual-novel "auto mode"
  /// beat that lets the reader absorb a line instead of having it scroll
  /// past. Scales with `displayLength` (longer line → longer pause) and the
  /// speed tier (slower tier → longer per-character pause); `.instant`
  /// returns `.zero` so Max playback keeps its no-gap behavior.
  ///
  /// **Sim-only.** Like ``charsPerSecond`` and ``interEventDelayMs`` this is
  /// a Sim-side pacing property: ``ReplayViewModel`` already paces turns via
  /// ``multiplier`` × `turnDelayMs`/`codePhaseDelayMs` and must NOT route
  /// through this — see the type-level "Consumers" note and the
  /// `multiplier` doc-comment's replay-only contract.
  ///
  /// **`displayLength` is the grapheme count of the committed _primary_ text**
  /// (``TurnOutput/primaryText(for:)`` — see the consumer in
  /// ``SimulationViewModel``). Inner-thought text is intentionally excluded,
  /// so thought-heavy turns are paced on their primary line only — an
  /// accepted approximation; revisit (`+ thoughtLength` when shown) only if
  /// manual QA shows under-pausing. Grapheme `.count` (not UTF-16) is the
  /// right reading-length proxy for Japanese / emoji.
  ///
  /// Formula: `min(base + perChar · max(0, displayLength), cap)`, clamped so
  /// a very long line cannot stall playback (or the cancellation window)
  /// past `cap`.
  ///
  /// Adding this method widens the public API surface, so it is
  /// SemVer-relevant per the type-level note above. Values are change-detector
  /// pinned by ``PlaybackSpeedTests``.
  public func readingDwell(displayLength: Int) -> Duration {
    let perCharMs: Double
    let baseMs: Double
    let capMs: Double
    switch self {
    // Per-tier constants tuned so the pause reads as a "let it land" beat on
    // top of the reveal, not a full re-read: at normal, a ~40-char line dwells
    // ~1.1s, ~100 chars ~2.1s, long lines clamp at 3.2s. Slower tiers dwell
    // longer per char and clamp higher; faster tiers shorter.
    case .slow:
      perCharMs = 28
      baseMs = 500
      capMs = 4500
    case .normal:
      perCharMs = 18
      baseMs = 350
      capMs = 3200
    case .fast:
      perCharMs = 10
      baseMs = 220
      capMs = 2200
    case .instant: return .zero
    }
    let clampedMs = min(baseMs + perCharMs * Double(max(0, displayLength)), capMs)
    return .milliseconds(Int(clampedMs))
  }

  /// User-facing label rendered via `Text(speed.label)`. Only `.instant`
  /// is wrapped in `String(localized:)` — the `x0.5`/`x1`/`x1.5` multiplier
  /// notation is universal across locales (Netflix / YouTube / Apple TV
  /// playback-control convention), same shape as
  /// ``InferenceStatsFormatter``'s `tok/s`/`s` carve-out per
  /// `docs/i18n/leak-detection.md`. ``PlaybackSpeedTests`` literal-pins all
  /// four labels as the regression guard against accidental wrap.
  public var label: String {
    switch self {
    case .slow: "x0.5"
    case .normal: "x1"
    case .fast: "x1.5"
    case .instant: String(localized: "Max")
    }
  }
}
