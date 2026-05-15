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
    #expect(LaunchAnimationConfig.iconSize == CGFloat(132))
    #expect(LaunchAnimationConfig.iconCornerRadius == CGFloat(30))
  }

  @Test func hapticDelayIsAtExpectedOffset() {
    let hapticDelay =
      LaunchAnimationConfig.coldDuration * LaunchAnimationConfig.hapticDelayRatio
    #expect(abs(hapticDelay - 0.88) < 1e-9)
  }
}
