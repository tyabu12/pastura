import Foundation

/// Pure presentation helpers for ``GalleryScenarioDetailView``'s enriched
/// metadata rows and the "What happens" phase-step section.
///
/// Extracted from the View so the mapping / hide-when-empty logic is
/// unit-testable without rendering (`.claude/rules/view-testing.md` rule 1).
///
/// Left at the default (MainActor) isolation — **not** `nonisolated` — because
/// ``phaseSteps(phases:)`` composes ``PhaseDisplayName/label(for:)`` and
/// ``PhaseGlyph/symbolName(for:)``, MainActor View-layer helpers; a
/// `nonisolated` enum passing those function values would drop the
/// `@MainActor` (swift-isolation.md Pattern 5). The test suite is therefore
/// `@MainActor`; MainActor can still call these directly.
enum GalleryScenarioDetailFormat {

  /// Ordered glyph + label steps for the "What happens" section, one per
  /// phase, derived from a gallery entry's `phases` raw strings.
  ///
  /// Each raw value is mapped through ``PhaseType`` → (``PhaseGlyph``,
  /// ``PhaseDisplayName``); unknown kinds (a feed newer than this build knows)
  /// are skipped, mirroring the lenient forward-compat posture of
  /// ``GalleryScenario/phases``. Returns `[]` — never `nil` — when `phases` is
  /// absent / empty **or** every entry mapped away (all-unknown), so the
  /// caller can hide the section on `.isEmpty` without an extra optional.
  static func phaseSteps(phases: [String]?) -> [(symbol: String, label: String)] {
    guard let phases else { return [] }
    return
      phases
      .compactMap { PhaseType(rawValue: $0) }
      .map { (symbol: PhaseGlyph.symbolName(for: $0), label: PhaseDisplayName.label(for: $0)) }
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

  /// Display-ready form of a curated highlight's YAML fragment (ADR-029).
  ///
  /// The published fragments are multi-line YAML blocks that commonly end with
  /// a trailing newline; rendered as-is inside a code-style block that trailing
  /// blank line reads as a stray empty row. Only **trailing** whitespace is
  /// trimmed — leading indentation is load-bearing in YAML, so the first line's
  /// offset is preserved exactly as published.
  static func yamlFragmentForDisplay(_ fragment: String) -> String {
    // `Character.isWhitespace` is true for "\n", "\r\n", and spaces alike,
    // so one predicate covers every trailing form. A hand-rolled loop rather
    // than `trimmingCharacters(in:)`, which trims BOTH ends and would break
    // the leading-indentation guarantee above.
    var trimmed = Substring(fragment)
    while let last = trimmed.last, last.isWhitespace {
      trimmed = trimmed.dropLast()
    }
    return String(trimmed)
  }

  /// Alert content for a **non-navigating** install outcome, or `nil` for the
  /// navigating ones (`.installed` / `.updated`, which push to the local copy
  /// instead of alerting). Extracted from the View so the copy — including the
  /// ADR-020 D5 `.updateRequired` forward-guidance (deliberately *not* a
  /// "download"/"parse" dead-end) — is unit-testable without rendering.
  static func installAlert(
    for outcome: SharedScenariosViewModel.TryOutcome
  ) -> OutcomeAlert? {
    switch outcome {
    case .installed, .updated:
      return nil
    case .conflict(let existingName, _):
      return OutcomeAlert(
        title: String(localized: "Cannot install"),
        message: String(
          format: String(
            localized:
              "A scenario named “%@” already uses this id. Delete or rename it first, then try again."
          ),
          existingName))
    case .hashMismatch:
      return OutcomeAlert(
        title: String(localized: "Integrity check failed"),
        message: String(
          localized:
            "The downloaded scenario does not match its expected signature. The gallery may have been updated. Pull to refresh and try again."
        ))
    case .networkError(let description):
      // description is a runtime error string from the network layer — not wrapped.
      return OutcomeAlert(title: String(localized: "Download failed"), message: description)
    case .updateRequired:
      return OutcomeAlert(
        title: String(localized: "Update required"),
        message: String(
          localized:
            "This scenario needs a newer version of Pastura. Update the app to run it."))
    }
  }
}
