import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ProgressThrottleTests {

  // MARK: - First call

  @Test func firstCallAlwaysReturnsTrue() {
    var throttle = ProgressThrottle()
    let now = ContinuousClock.now
    #expect(throttle.shouldEmit(now: now) == true)
  }

  @Test func firstCallWithCustomIntervalAlwaysReturnsTrue() {
    var throttle = ProgressThrottle(interval: .milliseconds(50))
    let now = ContinuousClock.now
    #expect(throttle.shouldEmit(now: now) == true)
  }

  // MARK: - Within interval

  @Test func secondCallWithinIntervalReturnsFalse() {
    var throttle = ProgressThrottle()
    let now = ContinuousClock.now
    _ = throttle.shouldEmit(now: now)
    // 50ms < 100ms default interval
    #expect(throttle.shouldEmit(now: now + .milliseconds(50)) == false)
  }

  // MARK: - Boundary semantics (>= interval)

  @Test func secondCallExactlyAtIntervalReturnsTrue() {
    var throttle = ProgressThrottle()
    let now = ContinuousClock.now
    _ = throttle.shouldEmit(now: now)
    // Exactly at the default 100ms interval — >= semantics means accepted.
    #expect(throttle.shouldEmit(now: now + .milliseconds(100)) == true)
  }

  @Test func secondCallPastIntervalReturnsTrue() {
    var throttle = ProgressThrottle()
    let now = ContinuousClock.now
    _ = throttle.shouldEmit(now: now)
    // 150ms > 100ms default interval
    #expect(throttle.shouldEmit(now: now + .milliseconds(150)) == true)
  }

  // MARK: - Window resets after accepted call

  @Test func windowResetsAfterAcceptedCall() {
    var throttle = ProgressThrottle()
    let now = ContinuousClock.now
    // t=0: accepted (first call)
    _ = throttle.shouldEmit(now: now)
    // t=100ms: accepted (>= interval since t=0)
    _ = throttle.shouldEmit(now: now + .milliseconds(100))
    // t=150ms: within interval of t=100ms — should be rejected
    #expect(throttle.shouldEmit(now: now + .milliseconds(150)) == false)
  }

  // MARK: - Skipped calls don't advance timestamp

  @Test func skippedCallsDoNotAdvanceStoredTimestamp() {
    var throttle = ProgressThrottle()
    let now = ContinuousClock.now
    // t=0: accepted (first call)
    _ = throttle.shouldEmit(now: now)
    // t=50ms: skipped (within interval of t=0)
    _ = throttle.shouldEmit(now: now + .milliseconds(50))
    // t=100ms: should be accepted (>= interval since t=0, the last accepted)
    #expect(throttle.shouldEmit(now: now + .milliseconds(100)) == true)
  }

  // MARK: - Custom interval

  @Test func customIntervalAcceptsAtBoundary() {
    var throttle = ProgressThrottle(interval: .milliseconds(50))
    let now = ContinuousClock.now
    _ = throttle.shouldEmit(now: now)
    // Exactly at 50ms — accepted under custom interval
    #expect(throttle.shouldEmit(now: now + .milliseconds(50)) == true)
  }

  @Test func customIntervalRejectsJustBeforeBoundary() {
    var throttle = ProgressThrottle(interval: .milliseconds(50))
    let now = ContinuousClock.now
    _ = throttle.shouldEmit(now: now)
    // 49ms < 50ms custom interval — rejected
    #expect(throttle.shouldEmit(now: now + .milliseconds(49)) == false)
  }
}
