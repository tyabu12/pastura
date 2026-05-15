import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct LaunchPhaseCoordinatorTests {

  // Bit-exact `Date` fixtures sidestep CI clock-skew flakiness on
  // boundary cases — see memory `feedback_ci_wallclock_test_bounds.md`.
  private static let now = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func firstLaunchYieldsCold() {
    let kind = LaunchPhaseCoordinator.nextLaunchKind(
      now: Self.now,
      lastBackgroundedAt: nil,
      threshold: LaunchAnimationConfig.warmThreshold
    )
    #expect(kind == .cold)
  }

  @Test func recentBackgroundYieldsWarm() {
    let lastBg = Self.now.addingTimeInterval(-30)  // 30s ago, well under 180s
    let kind = LaunchPhaseCoordinator.nextLaunchKind(
      now: Self.now,
      lastBackgroundedAt: lastBg,
      threshold: LaunchAnimationConfig.warmThreshold
    )
    #expect(kind == .warm)
  }

  @Test func atThresholdBoundaryYieldsWarm() {
    // Exactly at threshold should still count as warm — the spec wording
    // "elapsed ≤ threshold ⇒ warm" defines the boundary as inclusive.
    let lastBg = Self.now.addingTimeInterval(-LaunchAnimationConfig.warmThreshold)
    let kind = LaunchPhaseCoordinator.nextLaunchKind(
      now: Self.now,
      lastBackgroundedAt: lastBg,
      threshold: LaunchAnimationConfig.warmThreshold
    )
    #expect(kind == .warm)
  }

  @Test func pastThresholdYieldsCold() {
    let lastBg = Self.now.addingTimeInterval(-(LaunchAnimationConfig.warmThreshold + 1))
    let kind = LaunchPhaseCoordinator.nextLaunchKind(
      now: Self.now,
      lastBackgroundedAt: lastBg,
      threshold: LaunchAnimationConfig.warmThreshold
    )
    #expect(kind == .cold)
  }

  @Test @MainActor func recordBackgroundedStoresTimestamp() {
    let coordinator = LaunchPhaseCoordinator()
    #expect(coordinator.lastBackgroundedAt == nil)
    let timestamp = Self.now
    coordinator.recordBackgrounded(at: timestamp)
    #expect(coordinator.lastBackgroundedAt == timestamp)
  }

  @Test @MainActor func clearBackgroundedTimestampResetsToNil() {
    let coordinator = LaunchPhaseCoordinator()
    coordinator.recordBackgrounded(at: Self.now)
    coordinator.clearBackgrounded()
    #expect(coordinator.lastBackgroundedAt == nil)
  }
}
