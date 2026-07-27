import Testing

@testable import Pastura

/// Pure-logic tests for the Simulation completion-transition timing
/// (`.claude/rules/view-testing.md` rule 1 — extract logic to unit tests; the
/// animation timing itself stays code-review / manual-QA gated per rule 4).
@Suite("SimulationViewCompletionChrome", .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewCompletionChromeTests {

  @Test func completionChromeReadyTruthTable() {
    // The completion chrome (Export control + result card) is ready only once
    // the run has completed AND the final row's typewriter reveal has settled
    // (`latestRowRevealCompleted`). `isCompleted` alone fires a beat early on
    // long / multi-sentence / retried rows because the turn-pacing hold is a
    // predicted duration the real reveal outlasts.
    #expect(
      SimulationViewModel.completionChromeReady(
        isCompleted: false, latestRowRevealCompleted: false) == false)
    #expect(
      SimulationViewModel.completionChromeReady(
        isCompleted: false, latestRowRevealCompleted: true) == false)
    // Completed but the last row's reveal has not settled → hold chrome back.
    #expect(
      SimulationViewModel.completionChromeReady(
        isCompleted: true, latestRowRevealCompleted: false) == false)
    // Completed and the reveal has settled → show chrome.
    #expect(
      SimulationViewModel.completionChromeReady(
        isCompleted: true, latestRowRevealCompleted: true) == true)
  }

  @Test func sharedFadeDurationPinned() {
    // Change-detector on the shared completion-transition fade duration
    // (result-card fade-in + past-utterance focus dim). This is a
    // code-review-gated timing token with no automated firing signal — a
    // failure is NOT a bug, it means the value drifted (likely in an unrelated
    // refactor). Confirm the change passed review, then update the expectation.
    #expect(SimulationView.sharedFadeDuration == 0.35)
  }

  @Test func reviewPromptDelayPinned() {
    // Same change-detector rationale as above, for the gap between the result
    // card settling and the App Store review prompt (#1279). The value is
    // load-bearing product behaviour, not decoration: shrink it toward zero and
    // the system dialog covers the score reveal it is meant to reward.
    #expect(SimulationView.reviewPromptDelay == .seconds(2))
  }
}
