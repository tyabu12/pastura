import Foundation

/// Pure presentation helpers for ``GalleryScenarioDetailView``'s enriched
/// metadata rows and the "What happens" phase-flow section.
///
/// Extracted from the View so the mapping / hide-when-empty logic is
/// unit-testable without rendering (`.claude/rules/view-testing.md` rule 1).
///
/// Left at the default (MainActor) isolation — **not** `nonisolated` — because
/// ``phaseFlow(phases:)`` composes ``PhaseDisplayName/label(for:)``, a
/// MainActor View-layer helper; a `nonisolated` enum passing that function
/// value would drop the `@MainActor` (swift-isolation.md Pattern 5). The test
/// suite is therefore `@MainActor`; MainActor can still call these directly.
enum GalleryScenarioDetailFormat {

  /// Separator drawn between consecutive phase labels in the flow.
  static let phaseSeparator = " → "

  /// Ordered, human-readable phase flow for the "What happens" section,
  /// derived from a gallery entry's `phases` raw strings (e.g.
  /// `"Speak Each → Summarize"`).
  ///
  /// Each raw value is mapped through ``PhaseType`` → ``PhaseDisplayName``;
  /// unknown kinds (a feed newer than this build knows) are skipped, mirroring
  /// the lenient forward-compat posture of ``GalleryScenario/phases``. Returns
  /// `nil` — so the caller hides the section — when `phases` is absent / empty
  /// **or** every entry mapped away (all-unknown), so no empty section renders.
  static func phaseFlow(phases: [String]?) -> String? {
    guard let phases else { return nil }
    let labels =
      phases
      .compactMap { PhaseType(rawValue: $0) }
      .map(PhaseDisplayName.label(for:))
    guard !labels.isEmpty else { return nil }
    return labels.joined(separator: phaseSeparator)
  }

  /// Localized language name for a gallery entry's raw ISO 639-1 `language`
  /// code, or `nil` when absent / unrecognized so the Language row is hidden.
  ///
  /// Only the two launch languages are mapped explicitly (a finite localized
  /// switch mirroring ``GalleryCategory/displayName``) — an unknown code hides
  /// the row rather than surfacing a raw `"xx"` string. The caller passes the
  /// **raw** ``GalleryScenario/language`` (not ``GalleryScenario/effectiveLanguage``)
  /// so the nil default is preserved and hide-on-nil holds.
  static func languageLabel(code: String?) -> String? {
    switch code {
    case "ja": return String(localized: "Japanese")
    case "en": return String(localized: "English")
    default: return nil
    }
  }
}
