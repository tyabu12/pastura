import Testing

@testable import Pastura

/// Pins the contract of the shared `PhaseDisplayName.label(for:)`
/// helper that consolidates the formerly-duplicated phase-name switch
/// from `SimulationView` and `ModelDownloadHostView+PhaseLabels` into
/// a single localized source of truth (#314).
///
/// Assertions follow CLAUDE.md "Error message i18n prep" — partial
/// match against the English source token, never exact equality, so
/// future Step C-1 ja-string revisions do not break the test. The
/// distinctness invariant guards against accidental case fall-through
/// in the underlying switch (every phase must map to its own label).
/// We deliberately do NOT pin a specific English token per case: that
/// check would either be a no-op when device locale is `ja` (silent
/// pass via `||`-fallback) or would require locale pinning that
/// cross-cuts every test target — neither carries its weight.
///
/// The suite also pins the #882 "no snake_case in the UI" contract:
/// `PhaseTypeLabel` renders `PhaseDisplayName.label(for:)` (not
/// `rawValue`), and the `requiresLLM` split decides which phase markers
/// become full-width separators vs inline badges in the transcript.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PhaseDisplayNameTests {

  @Test func everyPhaseProducesNonEmptyLabel() {
    for phase in PhaseType.allCases {
      let label = PhaseDisplayName.label(for: phase)
      #expect(!label.isEmpty, "\(phase) should produce a non-empty label")
    }
  }

  @Test func everyPhaseMapsToDistinctLabel() {
    // Distinctness catches accidental case fall-through in the switch
    // that mere non-empty would miss (two phases both returning the
    // same string).
    let labels = Set(PhaseType.allCases.map { PhaseDisplayName.label(for: $0) })
    #expect(labels.count == PhaseType.allCases.count)
  }

  @Test func everyPhaseLabelIsSnakeCaseFree() {
    // #882: `PhaseTypeLabel` now renders this label instead of the
    // snake_case `rawValue`, so no phase-marker badge may surface a raw
    // `speak_all`-style token. Guarding the mapping (never `==` rawValue,
    // never contains `_`) is the ADR-009-compatible way to pin "no
    // snake_case in the UI" without rendering the view.
    for phase in PhaseType.allCases {
      let label = PhaseDisplayName.label(for: phase)
      #expect(!label.contains("_"), "\(phase) label \"\(label)\" leaks snake_case")
      #expect(label != phase.rawValue, "\(phase) label must differ from rawValue")
    }
  }

  @Test func llmPhasesDriveFullWidthSeparators() {
    // #882: SimulationView's `.phaseStarted` case renders LLM phases as
    // full-width separators and code phases as inline badges, gating on
    // exactly `PhaseType.requiresLLM`. Pinning the LLM set here is a
    // cheap non-render guard (ADR-009) against a future `requiresLLM`
    // change silently altering the transcript's separator layout.
    let llmPhases = PhaseType.allCases.filter(\.requiresLLM)
    #expect(
      Set(llmPhases) == [.speakAll, .speakEach, .vote, .choose, .reflect, .whisper, .narrate])
  }
}
