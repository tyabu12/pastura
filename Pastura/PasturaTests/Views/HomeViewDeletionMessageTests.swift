import Testing

@testable import Pastura

/// Unit-tests the pure copy-building helper behind HomeView's scenario-delete
/// confirmation (View-logic extraction per ADR-009 / view-testing rule).
@Suite(.timeLimit(.minutes(1)))
struct HomeViewDeletionMessageTests {

  @Test func interpolatesScenarioName() {
    let message = HomeView.scenarioDeletionMessage(name: "Word Wolf")
    #expect(message.contains("Word Wolf"))
  }

  @Test func reassuresThatPastResultsAreKept() {
    // The post-v7 behavior change: deletion no longer wipes history, so the
    // copy must say results are kept.
    let message = HomeView.scenarioDeletionMessage(name: "Any")
    #expect(message.contains("kept"))
  }
}
