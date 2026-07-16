import Testing

@testable import Pastura

/// Logic surface of `PersonaDetailSheet`'s secret spoiler (#914).
///
/// Per ADR-009 the reveal *rendering* is code-review-gated; what is unit-tested
/// here is the pure, extracted decision the View reads — the VoiceOver label,
/// which must state the action the tap performs rather than the current state
/// (matching the sibling INNER VOICE toggle in `AgentOutputRow`).
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PersonaDetailSheetSecretTests {

  @Test func collapsedLabelOffersToReveal() {
    #expect(
      PersonaDetailSheet.secretToggleAccessibilityLabel(showSecret: false)
        == "Peek at their secret")
  }

  @Test func expandedLabelOffersToHide() {
    #expect(PersonaDetailSheet.secretToggleAccessibilityLabel(showSecret: true) == "Hide secret")
  }

  /// The label must change with state — a static label would leave VoiceOver
  /// users unable to tell whether the secret is currently revealed.
  @Test func labelIsStateDependent() {
    #expect(
      PersonaDetailSheet.secretToggleAccessibilityLabel(showSecret: true)
        != PersonaDetailSheet.secretToggleAccessibilityLabel(showSecret: false))
  }
}
