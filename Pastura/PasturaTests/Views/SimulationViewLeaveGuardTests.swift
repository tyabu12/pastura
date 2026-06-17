import Testing

@testable import Pastura

// `@MainActor` because `shouldGuardLeave` is a static on the default-MainActor
// `SimulationView`; the suite isolation lets a nonisolated caller reach it
// (`.claude/rules/swift-isolation.md` Pattern 5).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SimulationViewLeaveGuardTests {

  @Test func guardsWhenRunningNotPausedNotCompleted() {
    // The only state that risks a silent loss: an in-flight run the user hasn't
    // explicitly paused. Leaving it must be confirmed (#673).
    #expect(SimulationView.shouldGuardLeave(isRunning: true, isPaused: false, isCompleted: false))
  }

  @Test func noGuardWhenNotRunning() {
    #expect(!SimulationView.shouldGuardLeave(isRunning: false, isPaused: false, isCompleted: false))
  }

  @Test func noGuardWhenPaused() {
    // A paused run is already persisted as `.paused` — leaving loses nothing.
    #expect(!SimulationView.shouldGuardLeave(isRunning: true, isPaused: true, isCompleted: false))
  }

  @Test func noGuardWhenCompleted() {
    // A completed run has its terminal `.completed` row — nothing to confirm.
    #expect(!SimulationView.shouldGuardLeave(isRunning: true, isPaused: false, isCompleted: true))
  }
}
