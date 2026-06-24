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

  /// Description line limit: up to two truncated lines at normal Dynamic Type
  /// sizes (aligned to the Shared Scenarios row), but unlimited so the text
  /// wraps at accessibility sizes — clipping to two lines at AX5 would drop
  /// most of it. `nil` means "no limit" to SwiftUI's `.lineLimit(_:)`.
  static func descriptionLineLimit(isAccessibilitySize: Bool) -> Int? {
    isAccessibilitySize ? nil : 2
  }

  /// Localized leading caption for the gallery category (#748), or nil when
  /// the scenario carries no category (local / self-made / preset → no badge)
  /// or the persisted raw value no longer maps to a `GalleryCategory` case (a
  /// case removed in a future version reading an old row — degrade to nil
  /// rather than show a stale token). `nil` ⇒ the caption shows the inference
  /// count alone, with no dangling separator.
  static func categoryCaption(for category: String?) -> String? {
    category.flatMap { GalleryCategory(rawValue: $0)?.displayName }
  }

  /// Progress label for the paused "resume" card — "Round X / Y", reusing the
  /// existing `Round %lld / %lld` catalog key. nil when the total round count
  /// is unknown (orphaned run / name-only metadata) so the caller hides the
  /// progress segment rather than rendering a half-pair.
  static func pausedProgressLabel(currentRound: Int, totalRounds: Int?) -> String? {
    guard let totalRounds, totalRounds > 0 else { return nil }
    return String(format: String(localized: "Round %lld / %lld"), currentRound, totalRounds)
  }

  // MARK: - Compact row (案C — tab-identity PR3)

  /// Leading provenance segment for the editorial compact row's caption — and
  /// the single source of truth for ``usesDocIcon(isPreset:category:)`` so the
  /// icon and the caption never disagree:
  /// - **Preset** for bundled presets.
  /// - the gallery **category** display name for gallery-installed scenarios
  ///   (reuses ``categoryCaption(for:)``, #748).
  /// - **Self-made** otherwise — a self-authored scenario with no resolvable
  ///   category. A persisted-but-unmappable category degrades here too
  ///   (``categoryCaption(for:)`` ⇒ nil), so a stale gallery row reads as
  ///   self-made rather than showing a dropped token; an acceptable trade for
  ///   one rare forward-compat case in exchange for icon/caption consistency.
  static func provenanceCaption(isPreset: Bool, category: String?) -> String {
    if isPreset { return String(localized: "Preset") }
    if let categoryName = categoryCaption(for: category) { return categoryName }
    return String(localized: "Self-made")
  }

  /// The compact row's caption as ordered, already-localized segments the
  /// caller joins with `·`: `[provenance, "N agents"?, "N rounds"?]`. Provenance
  /// is always present; the agent and round halves drop out when unknown so the
  /// caller never renders a dangling separator (same guard shape as
  /// ``ScenarioSummaryRowFormat/captionSegments(leading:trailing:)``).
  ///
  /// The count halves are built through `String(format: String(localized:), n)`
  /// — **never** the bare `%lld …` catalog key, which would render the literal
  /// `%lld` (`.claude/rules/i18n.md` § "Format-string pattern").
  static func compactCaptionSegments(
    isPreset: Bool, category: String?, agentCount: Int?, rounds: Int?
  ) -> [String] {
    var segments = [provenanceCaption(isPreset: isPreset, category: category)]
    if let agentCount, agentCount > 0 {
      segments.append(String(format: String(localized: "%lld agents"), agentCount))
    }
    if let roundsLabel = roundsLabel(rounds: rounds) {
      segments.append(roundsLabel)
    }
    return segments
  }

  /// Description line limit for the compact row: a single truncated line at
  /// normal Dynamic Type sizes (denser than the old Home row's two), but
  /// unlimited so the text wraps at accessibility sizes — clipping to one line
  /// at AX5 would drop almost all of it. `nil` means "no limit" to
  /// SwiftUI's `.lineLimit(_:)`.
  static func compactDescriptionLineLimit(isAccessibilitySize: Bool) -> Int? {
    isAccessibilitySize ? nil : 1
  }

  /// Whether the compact row draws a document glyph instead of a sheep avatar
  /// in its leading icon tile. Document only for self-authored scenarios (no
  /// preset, no resolvable gallery category); presets and gallery-installed
  /// scenarios show a sheep. Keyed on the same classification as
  /// ``provenanceCaption(isPreset:category:)`` so icon and caption agree.
  static func usesDocIcon(isPreset: Bool, category: String?) -> Bool {
    !isPreset && categoryCaption(for: category) == nil
  }
}
