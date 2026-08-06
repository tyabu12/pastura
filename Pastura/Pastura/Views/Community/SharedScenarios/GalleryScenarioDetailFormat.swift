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

  /// One rendered line of a curated highlight's excerpt, resolved for the run
  /// figure (ADR-029).
  ///
  /// Built by ``excerptRows(_:totalRounds:)``, which owns the two derivations a
  /// raw ``GalleryHighlightExcerptEntry`` cannot answer for itself: which avatar
  /// colour slot the speaker occupies, and whether a round boundary opens above
  /// this line.
  struct ExcerptRow: Identifiable {
    /// Position in the excerpt. The entries are **not** unique — one persona
    /// can speak more than once, and two lines can be byte-identical (both
    /// shipped highlights contain a repeated `"答えはC"`) — so the index is the
    /// only stable identity, mirroring the `enumerated().offset` ids the rest
    /// of this screen uses.
    let id: Int

    let entry: GalleryHighlightExcerptEntry

    /// Zero-based avatar colour slot. See ``excerptRows(_:totalRounds:)`` for
    /// how it is derived and why it matches the app's own resolution.
    let agentPosition: Int

    /// Mapped phase, for the row's badge. Non-optional: `GalleryHighlightLoader`
    /// hides any highlight carrying an unmappable phase (ADR-029 § Amendment
    /// 2026-08-07), so a row that exists always has one.
    let phaseType: PhaseType

    /// Localized round label for a divider drawn **above** this row, or `nil`
    /// when the line continues the previous line's round.
    let dividerLabel: String?
  }

  /// Resolves a curated excerpt into render-ready rows.
  ///
  /// **Avatar slots follow order of first appearance.** The app assigns a
  /// speaker's colour from their index in the scenario's persona list
  /// (``SheepAvatar/Character/forAgent(_:position:)`` → `allCases[position % 4]`),
  /// but a highlight file carries no persona index — it is an excerpt, not a
  /// scenario. First appearance within the excerpt stands in for it. Measured on
  /// both shipped highlights, the two orders agree, so a reader sees the same
  /// colours here as in a real run; `web/src/components/ScenarioLanding.astro`
  /// resolves the landing pages the same way for the same reason. With five or
  /// more speakers the fourth and fifth collide — the app collides identically,
  /// so reproducing it is fidelity rather than a defect to route around.
  ///
  /// **Returns `[]` when any phase is unmappable.** This mirrors the loader's
  /// fail-closed gate rather than trusting it: this is a pure function with no
  /// way to signal a partial result, and the alternatives — dropping the line,
  /// or inventing a fallback badge — are the two outcomes ADR-029 § Amendment
  /// 2026-08-07 rejects. In production the loader has already hidden such a
  /// highlight, so this path is defence in depth and not the live guard.
  ///
  /// - Parameter totalRounds: the scenario's round count
  ///   (``GalleryScenario/rounds``), or `nil` when the feed omits it — divider
  ///   labels then fall back to the total-less form.
  static func excerptRows(
    _ excerpt: [GalleryHighlightExcerptEntry], totalRounds: Int?
  ) -> [ExcerptRow] {
    var slots: [String: Int] = [:]
    var rows: [ExcerptRow] = []

    for (index, entry) in excerpt.enumerated() {
      guard let phaseType = PhaseType(rawValue: entry.phase) else { return [] }

      let position = slots[entry.agent] ?? slots.count
      slots[entry.agent] = position

      let opensNewRound = index > 0 && entry.round != excerpt[index - 1].round
      rows.append(
        ExcerptRow(
          id: index,
          entry: entry,
          agentPosition: position,
          phaseType: phaseType,
          dividerLabel: opensNewRound
            ? roundLabel(round: entry.round, totalRounds: totalRounds) : nil))
    }
    return rows
  }

  /// Round label for the run figure's head, or `nil` to collapse the fragment.
  ///
  /// Reads the **first excerpt entry's** round, not round 1: a highlight is
  /// typically quoted from partway into a run, and the head is describing the
  /// passage below it rather than the scenario. `web`'s landing pages take
  /// `excerpt[0].round` for the same reason.
  ///
  /// Collapses when the excerpt is empty or ``GalleryScenario/rounds`` is
  /// absent — the head states a position within a whole, so it needs both
  /// halves, the same pair-or-nothing semantic ``GameHeaderRound`` enforces for
  /// the live header. A divider is not held to this: it separates two rounds
  /// that are both present in the passage, so it degrades to the total-less
  /// form instead of vanishing.
  static func excerptHeadRoundLabel(
    _ excerpt: [GalleryHighlightExcerptEntry], totalRounds: Int?
  ) -> String? {
    guard let first = excerpt.first, let totalRounds else { return nil }
    return GameHeader.formatRoundLabel(current: first.round, total: totalRounds)
  }

  /// `Round N / M`, or `Round N` when the total is unknown.
  ///
  /// Both keys already ship with `ja` translations — the two-argument form via
  /// ``GameHeader/formatRoundLabel(current:total:)`` (shared with the live
  /// header and the demo's round separators) and the one-argument form via the
  /// past-results round separator — so neither adds a catalog entry.
  static func roundLabel(round: Int, totalRounds: Int?) -> String {
    guard let totalRounds else {
      return String(format: String(localized: "Round %lld"), round)
    }
    return GameHeader.formatRoundLabel(current: round, total: totalRounds)
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
