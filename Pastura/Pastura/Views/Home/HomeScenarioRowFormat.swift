import Foundation

/// Pure display-formatting helpers for the Home scenario list row
/// (ADR-016 D3 row layout: name / sheep×agentCount · rounds / description).
///
/// Kept `nonisolated` and side-effect-free so the row's non-trivial display
/// logic — sheep-count clamping, the rounds label, meta-line visibility, and
/// the Dynamic-Type description line limit — is unit-testable without
/// rendering (ADR-009 / `.claude/rules/view-testing.md`: extract logic, never
/// assert rendered output).
nonisolated enum HomeScenarioRowFormat {
  /// Maximum sheep avatars drawn in one row before clamping. The exact agent
  /// count is secondary garnish the user doesn't act on in the list, so a
  /// clamp keeps the row legible and within width instead of overflowing for
  /// large casts. VoiceOver still announces the true count (see the row's
  /// `%lld agents` accessibility label).
  static let maxRowSheep = 5

  /// Number of sheep faces to draw for `agentCount`, clamped to
  /// ``maxRowSheep``. Returns 0 when the count is unknown (name-only metadata
  /// retrogression on a YAML parse failure) so the caller draws no faces.
  static func rowSheepCount(agentCount: Int?) -> Int {
    guard let agentCount, agentCount > 0 else { return 0 }
    return min(agentCount, maxRowSheep)
  }

  /// Localized "N rounds" label, or nil when the round count is unknown
  /// (metadata retrogression) so the caller hides the segment rather than
  /// rendering a dangling separator. Form B per `.claude/rules/i18n.md`.
  static func roundsLabel(rounds: Int?) -> String? {
    guard let rounds, rounds > 0 else { return nil }
    return String(format: String(localized: "%lld rounds"), rounds)
  }

  /// Whether the meta line (sheep + rounds) renders at all. Hidden when both
  /// the agent count and round count are unknown — an otherwise-empty meta
  /// line would still reserve vertical space and could leave a stray dot.
  static func showsMetaLine(agentCount: Int?, rounds: Int?) -> Bool {
    rowSheepCount(agentCount: agentCount) > 0 || roundsLabel(rounds: rounds) != nil
  }

  /// Description line limit: a single truncated line at normal Dynamic Type
  /// sizes (d3 design), but unlimited so the text wraps at accessibility
  /// sizes — clipping a description to one line at AX5 would drop most of it.
  /// `nil` means "no limit" to SwiftUI's `.lineLimit(_:)`.
  static func descriptionLineLimit(isAccessibilitySize: Bool) -> Int? {
    isAccessibilitySize ? nil : 1
  }

  /// Progress label for the paused "resume" card — "Round X / Y", reusing the
  /// existing `Round %lld / %lld` catalog key. nil when the total round count
  /// is unknown (orphaned run / name-only metadata) so the caller hides the
  /// progress segment rather than rendering a half-pair.
  static func pausedProgressLabel(currentRound: Int, totalRounds: Int?) -> String? {
    guard let totalRounds, totalRounds > 0 else { return nil }
    return String(format: String(localized: "Round %lld / %lld"), currentRound, totalRounds)
  }
}
