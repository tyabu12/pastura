import Foundation
import Testing

@testable import Pastura

/// Pure-value tests for the memoryWarning policy. Independently testable so
/// we can exercise edge cases (burst firing, escalation window boundaries,
/// already-paused, BG branch) without synthesizing SwiftUI scenePhase.
@Suite(.timeLimit(.minutes(1)))
struct MemoryWarningThrottleTests {

  // MARK: - Already-paused no-op

  @Test func alreadyPausedFGIgnoresWarning() {
    var throttle = MemoryWarningThrottle()
    let decision = throttle.decide(isActive: true, isPaused: true, now: Date())
    #expect(decision == .ignore)
  }

  @Test func alreadyPausedBGAlsoIgnores() {
    // The "ignore-when-paused" rule wins over the BG cancel rule. Reasoning:
    // a paused simulation has no in-flight inference, so cancel offers no
    // additional memory relief beyond what pause already achieves at the
    // model level. Letting iOS jetsam at this point is acceptable.
    var throttle = MemoryWarningThrottle()
    let decision = throttle.decide(isActive: false, isPaused: true, now: Date())
    #expect(decision == .ignore)
  }

  // MARK: - Background branch

  @Test func backgroundCancelsImmediately() {
    var throttle = MemoryWarningThrottle()
    let decision = throttle.decide(isActive: false, isPaused: false, now: Date())
    #expect(decision == .cancelDueToBackground)
  }

  @Test func inactiveTreatedAsBackground() {
    // The View passes `isActive: scenePhase == .active`, so .inactive arrives
    // here as `isActive: false` — same branch as .background. Closes the
    // .active → .inactive → .background transition race.
    var throttle = MemoryWarningThrottle()
    let decision = throttle.decide(isActive: false, isPaused: false, now: Date())
    #expect(decision == .cancelDueToBackground)
  }

  // MARK: - Foreground escalation

  @Test func foregroundFirstWarningPauses() {
    var throttle = MemoryWarningThrottle()
    let decision = throttle.decide(isActive: true, isPaused: false, now: Date())
    #expect(decision == .pauseAndLog)
  }

  @Test func secondWarningWithin30sEscalatesToCancel() {
    var throttle = MemoryWarningThrottle()
    let now = Date()
    #expect(throttle.decide(isActive: true, isPaused: false, now: now) == .pauseAndLog)
    #expect(
      throttle.decide(isActive: true, isPaused: false, now: now.addingTimeInterval(15))
        == .cancelDueToEscalation
    )
  }

  @Test func secondWarningAfter30sStartsFreshWindow() {
    var throttle = MemoryWarningThrottle()
    let now = Date()
    #expect(throttle.decide(isActive: true, isPaused: false, now: now) == .pauseAndLog)
    // 31s later is outside the window — counter resets, treated as a fresh
    // first warning, returns .pauseAndLog (not .cancelDueToEscalation).
    #expect(
      throttle.decide(isActive: true, isPaused: false, now: now.addingTimeInterval(31))
        == .pauseAndLog
    )
  }

  @Test func burstOfWarningsEscalatesOnSecond() {
    var throttle = MemoryWarningThrottle()
    let now = Date()
    var decisions: [MemoryWarningThrottle.Decision] = []
    // Simulate iOS bursting 5 warnings in 100ms.
    for offset in 0..<5 {
      decisions.append(
        throttle.decide(
          isActive: true, isPaused: false, now: now.addingTimeInterval(0.02 * Double(offset))
        )
      )
    }
    #expect(decisions[0] == .pauseAndLog)
    // Every subsequent one inside the window is .cancelDueToEscalation.
    // The View's `vm.isCancelled` guard prevents re-entry in practice.
    for decision in decisions.dropFirst() {
      #expect(decision == .cancelDueToEscalation)
    }
  }

  // MARK: - Reset semantics

  @Test func resetClearsCounter() {
    var throttle = MemoryWarningThrottle()
    let now = Date()
    _ = throttle.decide(isActive: true, isPaused: false, now: now)
    throttle.reset()
    // After reset, a warning at any subsequent time is treated as fresh.
    #expect(
      throttle.decide(isActive: true, isPaused: false, now: now.addingTimeInterval(5))
        == .pauseAndLog
    )
  }

  @Test func resetPreventsImmediateCancelAfterUserResume() {
    // Real-world scenario from critic Axis 2:
    //   1. Warning #1 → pause (count=1)
    //   2. User taps resume → SimulationView calls reset()
    //   3. Warning #2 within 30s of #1 — should NOT immediately cancel
    var throttle = MemoryWarningThrottle()
    let now = Date()
    _ = throttle.decide(isActive: true, isPaused: false, now: now)
    throttle.reset()
    #expect(
      throttle.decide(isActive: true, isPaused: false, now: now.addingTimeInterval(10))
        == .pauseAndLog
    )
  }
}
