import Foundation

/// Pure-logic source-of-truth for the picker's first-paint choreography.
///
/// `ModelPickerView` reads `@Environment(\.accessibilityReduceMotion)` and
/// forwards it as `reduceMotion: Bool` to these functions for each
/// `.animation(...)` call site. No `@Environment` access lives in this
/// type — it stays a pure function library so tests can plant boundary
/// cases without a `View` context. Per ADR-009, this is the recommended
/// extract pattern: pure-logic surface → unit-tests, view body
/// composition → manual QA + code-review.
///
/// Why not own `reduceMotion` on `ModelSelectionState`: that would
/// require a `View`-driven `state.reduceMotion = reduceMotion` bridge
/// inside the body and create a second source of truth for an
/// environment-derived value. Keeping `ModelSelectionState` to navigation-
/// path-level state matches the ADR-008 `AppRouter` scope philosophy.
///
/// Returning `nil` (rather than `0`) under reduceMotion is intentional:
/// the View applies `.animation(duration.map { … }, value: …)`, and
/// passing `nil` through `Optional.map` produces no animation at all —
/// stronger guarantee than a 0-duration `.easeOut` which still triggers
/// frame transitions on some iOS minor versions.
nonisolated enum ModelSelectionAnimations {

  /// The discrete entry-animation phases of the picker. Each phase is
  /// independent — a future redesign can extend / replace without
  /// touching call sites for unaffected phases. `modelRow` carries an
  /// index to drive the cumulative stagger delay.
  nonisolated enum Phase: Equatable {
    /// Caption ("PASTURA · SETUP") + H1 + subtitle fadeUp together.
    case header
    /// Horizon line scaleX 0 → 1 between header and list.
    case horizon
    /// Per-model row "sheepIn" with staggered delay by index.
    case modelRow(index: Int)
  }

  /// Animation duration in seconds, or `nil` under reduceMotion.
  static func animationDuration(reduceMotion: Bool, phase: Phase) -> Double? {
    guard !reduceMotion else { return nil }
    switch phase {
    case .header:
      return 1.0
    case .horizon:
      return 1.6
    case .modelRow:
      return 1.0
    }
  }

  /// Animation delay in seconds, or `nil` under reduceMotion.
  ///
  /// `modelRow` delay is `0.55 + 0.18 × index` — the spec stagger that
  /// reads as the sheep waking one-at-a-time. Index 0 → 0.55s,
  /// index 1 → 0.73s, etc. Non-negative indices only; callers pass
  /// `index >= 0` from `ForEach` enumeration.
  static func animationDelay(reduceMotion: Bool, phase: Phase) -> Double? {
    guard !reduceMotion else { return nil }
    switch phase {
    case .header:
      return 0.15
    case .horizon:
      return 0.3
    case .modelRow(let index):
      return 0.55 + 0.18 * Double(index)
    }
  }
}
