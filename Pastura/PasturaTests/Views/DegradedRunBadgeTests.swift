import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DegradedRunBadgeTests {

  @Test func completedWithMultipleSkippedTurnsShowsCount() {
    let result = DegradedRunBadge.skippedTurnCount(status: .completed, degradedTurnCount: 3)
    #expect(result == 3)
  }

  @Test func completedWithSingleSkippedTurnShowsCount() {
    let result = DegradedRunBadge.skippedTurnCount(status: .completed, degradedTurnCount: 1)
    #expect(result == 1)
  }

  @Test func completedWithZeroSkippedTurnsHidesBadge() {
    let result = DegradedRunBadge.skippedTurnCount(status: .completed, degradedTurnCount: 0)
    #expect(result == nil)
  }

  @Test func failedRunHidesBadgeEvenWithSkippedTurns() {
    let result = DegradedRunBadge.skippedTurnCount(status: .failed, degradedTurnCount: 5)
    #expect(result == nil)
  }

  @Test func pausedRunHidesBadge() {
    let result = DegradedRunBadge.skippedTurnCount(status: .paused, degradedTurnCount: 2)
    #expect(result == nil)
  }

  @Test func runningRunHidesBadge() {
    let result = DegradedRunBadge.skippedTurnCount(status: .running, degradedTurnCount: 2)
    #expect(result == nil)
  }

  @Test func cancelledRunHidesBadge() {
    let result = DegradedRunBadge.skippedTurnCount(status: .cancelled, degradedTurnCount: 2)
    #expect(result == nil)
  }

  @Test func nilStatusHidesBadge() {
    let result = DegradedRunBadge.skippedTurnCount(status: nil, degradedTurnCount: 4)
    #expect(result == nil)
  }
}
