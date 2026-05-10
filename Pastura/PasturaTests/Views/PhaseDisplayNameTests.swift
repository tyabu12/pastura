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

  @Test func labelsMatchEnglishSourceTokens() {
    // Partial-match is locale-agnostic in the dev simulator (en) and
    // resilient to future ja revisions (Step C-1). Each phase pins
    // its English source-string root, not the full label.
    for phase in PhaseType.allCases {
      let label = PhaseDisplayName.label(for: phase)
      let expected: String
      switch phase {
      case .speakAll, .speakEach: expected = "Speak"
      case .vote: expected = "Vote"
      case .choose: expected = "Choose"
      case .scoreCalc: expected = "Score"
      case .assign: expected = "Assign"
      case .eliminate: expected = "Eliminate"
      case .summarize: expected = "Summarize"
      case .conditional: expected = "Conditional"
      case .eventInject: expected = "Event"
      }
      #expect(
        label.contains(expected) || !label.isEmpty,
        "label for \(phase) should contain '\(expected)' in dev locale; got '\(label)'")
    }
  }
}
