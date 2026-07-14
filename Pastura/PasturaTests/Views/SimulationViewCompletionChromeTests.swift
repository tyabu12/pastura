import Testing

@testable import Pastura

/// Pure-logic tests for `SimulationView`'s completion-transition timing
/// (`.claude/rules/view-testing.md` rule 1 — extract View logic to unit tests;
/// the animation timing itself stays code-review / manual-QA gated per rule 4).
@Suite("SimulationViewCompletionChrome", .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewCompletionChromeTests {

  @Test func completionChromeReadyTruthTable() {
    // The completion chrome (Export control + result card) is ready only once
    // the run has completed AND the final row's typewriter reveal (inner voice
    // included) has settled. `isCompleted` alone fires a beat early because it
    // is driven off a predicted typing hold, so gate on the ground-truth
    // `latestRowIsAnimating` signal too.
    #expect(
      SimulationView.completionChromeReady(
        isCompleted: false, latestRowIsAnimating: false) == false)
    #expect(
      SimulationView.completionChromeReady(
        isCompleted: false, latestRowIsAnimating: true) == false)
    // Completed but the last inner voice is still typing → hold chrome back.
    #expect(
      SimulationView.completionChromeReady(
        isCompleted: true, latestRowIsAnimating: true) == false)
    // Completed and the reveal has settled → show chrome. (Instant speed and
    // empty rows never set `latestRowIsAnimating` true, so this branch also
    // covers their immediate-show case.)
    #expect(
      SimulationView.completionChromeReady(
        isCompleted: true, latestRowIsAnimating: false) == true)
  }

  @Test func sharedFadeDurationPinned() {
    // Change-detector on the shared completion-transition fade duration
    // (result-card fade-in + past-utterance focus dim). This is a
    // code-review-gated timing token with no automated firing signal — a
    // failure is NOT a bug, it means the value drifted (likely in an unrelated
    // refactor). Confirm the change passed review, then update the expectation.
    #expect(SimulationView.sharedFadeDuration == 0.35)
  }
}
