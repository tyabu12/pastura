import CoreGraphics
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct LaunchAnimationConfigTests {

  @Test func coldIsLongerThanWarm() {
    #expect(LaunchAnimationConfig.coldDuration > LaunchAnimationConfig.warmDuration)
  }

  @Test func warmThresholdLargerThanColdDuration() {
    #expect(LaunchAnimationConfig.warmThreshold > LaunchAnimationConfig.coldDuration)
  }

  @Test func hapticDelayRatioIsInUnitInterval() {
    #expect(LaunchAnimationConfig.hapticDelayRatio > 0)
    #expect(LaunchAnimationConfig.hapticDelayRatio < 1)
  }

  @Test func reducedMotionIsShorterThanAllDurations() {
    #expect(
      LaunchAnimationConfig.reducedMotionDuration < LaunchAnimationConfig.coldDuration)
    #expect(
      LaunchAnimationConfig.reducedMotionDuration < LaunchAnimationConfig.warmDuration)
  }

  @Test func designTokenFidelity() {
    // Canonical-value reminders. If these change, also regenerate
    // `LaunchIcon.imageset` (iconSize * {1,2,3}) and verify the static
    // LaunchScreen lands at the same on-screen size as the cold splash's
    // 0 % frame.
    #expect(LaunchAnimationConfig.iconSize == CGFloat(106))
    #expect(LaunchAnimationConfig.iconCornerRadius == CGFloat(30))
  }

  @Test func hapticDelayIsAtExpectedOffset() {
    // 1.2 s × 0.65 = 0.78 s — the "sheep arrival" beat.
    let hapticDelay =
      LaunchAnimationConfig.coldDuration * LaunchAnimationConfig.hapticDelayRatio
    #expect(abs(hapticDelay - 0.78) < 1e-9)
  }
}
