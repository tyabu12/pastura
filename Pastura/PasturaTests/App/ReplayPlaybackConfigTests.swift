import Testing

@testable import Pastura

/// Contract tests for ``ReplayPlaybackConfig``'s typing-cadence knob.
///
/// `typingCharsPerSecond` is the single source of truth for the demo
/// replay's character-reveal rate, read by both the View (``AgentOutputRow``
/// via ``ModelDownloadHostView``) and the ``ReplayViewModel`` pacing floor.
/// It defaults to `nil` (no proportional dwell / instant text) so legacy
/// configs and timing-sensitive tests are unaffected; only ``demoDefault``
/// opts in.
@Suite(.timeLimit(.minutes(1)))
struct ReplayPlaybackConfigTests {
  @Test func typingCharsPerSecondDefaultsToNil() {
    let config = ReplayPlaybackConfig(
      loopBehaviour: .loop, onComplete: .stopPlayback)
    #expect(config.typingCharsPerSecond == nil)
  }

  @Test func demoDefaultOptsIntoNormalTypingSpeed() {
    #expect(
      ReplayPlaybackConfig.demoDefault.typingCharsPerSecond
        == PlaybackSpeed.normal.charsPerSecond)
    // Pins the concrete value so a future PlaybackSpeed.normal change is a
    // deliberate, reviewed edit rather than a silent demo-cadence shift.
    #expect(ReplayPlaybackConfig.demoDefault.typingCharsPerSecond == 30)
  }
}
