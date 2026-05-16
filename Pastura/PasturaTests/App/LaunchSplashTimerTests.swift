import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct LaunchSplashTimerTests {

  // Design-handoff values: min 1.6s, extension up to +1.0s.
  private static let minDuration: TimeInterval = 1.6
  private static let maxExtension: TimeInterval = 1.0
  private static let hardDeadline: TimeInterval = 2.6  // = min + ext

  @Test func earlyReadyHoldsUntilMinDuration() {
    // Init resolves at 0.5s — splash must still hold the full 1.6s.
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: 0.5
    )
    #expect(dismissal == Self.minDuration)
  }

  @Test func onTimeReadyDismissesAtMinDuration() {
    // Init resolves exactly at 1.6s — dismissal coincides.
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: Self.minDuration
    )
    #expect(dismissal == Self.minDuration)
  }

  @Test func readyWithinExtensionDismissesImmediately() {
    // Init resolves at 2.0s — splash dismisses at 2.0s (no further hold).
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: 2.0
    )
    #expect(dismissal == 2.0)
  }

  @Test func readyAtHardDeadlineDismissesAtDeadline() {
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: Self.hardDeadline
    )
    #expect(dismissal == Self.hardDeadline)
  }

  @Test func readyBeyondHardDeadlineCapsAtDeadline() {
    // Init still slow at 3.0s — splash already gone at 2.6s.
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: 3.0
    )
    #expect(dismissal == Self.hardDeadline)
  }

  @Test func notReadyDismissesAtHardDeadline() {
    // Init never resolved — splash gives up at the hard deadline.
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: nil
    )
    #expect(dismissal == Self.hardDeadline)
  }

  @Test func picker400msTransitionDoesNotExtend() {
    // Locked-in semantics from plan: ".needsModelSelection at 400ms ⇒
    // splash dismisses at 1600ms baseline, not extended". This proves
    // that picker / DL-host emerging early does not delay splash death.
    let dismissal = LaunchSplashTimer.dismissalTime(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension,
      readyAt: 0.4
    )
    #expect(dismissal == Self.minDuration)
  }

  @Test func hardDeadlineMatchesMinPlusExtension() {
    let timer = LaunchSplashTimer(
      minDuration: Self.minDuration,
      maxExtension: Self.maxExtension
    )
    #expect(timer.hardDeadline == Self.hardDeadline)
  }
}
