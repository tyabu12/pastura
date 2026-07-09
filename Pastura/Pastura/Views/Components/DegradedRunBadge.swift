import Foundation

/// Pure gating logic for the degraded-run badge (ADR-021 D6): a run that
/// reached `.completed` with one or more skipped LLM turns shows an
/// "N turns skipped" annotation. Extracted so the show/hide decision is
/// unit-testable without rendering the View (ADR-009). The localized
/// rendering lives at the call sites (Results row / detail); this type
/// intentionally holds no user-facing string.
enum DegradedRunBadge {
  /// The skip count to display, or `nil` when the badge must be hidden.
  ///
  /// Shown only for a **completed** run with a positive count — the badge
  /// is a completion-quality annotation, so a `.failed` / `.paused` /
  /// `.running` / `.cancelled` run (or a `nil`/unrecognized status) and a
  /// zero count both yield `nil`. `degradedTurnCount` is clamped implicitly
  /// by the `> 0` gate, so a negative value (never expected) also hides.
  static func skippedTurnCount(
    status: SimulationStatus?, degradedTurnCount: Int
  ) -> Int? {
    guard status == .completed, degradedTurnCount > 0 else { return nil }
    return degradedTurnCount
  }
}
