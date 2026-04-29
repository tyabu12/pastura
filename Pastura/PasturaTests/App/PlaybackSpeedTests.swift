import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PlaybackSpeedTests {
  @Test func allCasesEnumerated() {
    #expect(PlaybackSpeed.allCases == [.slow, .normal, .fast, .instant])
  }

  @Test func charsPerSecondValues() {
    #expect(PlaybackSpeed.slow.charsPerSecond == 15)
    #expect(PlaybackSpeed.normal.charsPerSecond == 30)
    #expect(PlaybackSpeed.fast.charsPerSecond == 45)
    #expect(PlaybackSpeed.instant.charsPerSecond == nil)
  }

  @Test func interEventDelayMsValues() {
    // Paced speeds share a small delay so round/phase transitions remain
    // perceptible; instant skips pacing entirely.
    #expect(PlaybackSpeed.slow.interEventDelayMs == 120)
    #expect(PlaybackSpeed.normal.interEventDelayMs == 120)
    #expect(PlaybackSpeed.fast.interEventDelayMs == 120)
    #expect(PlaybackSpeed.instant.interEventDelayMs == 0)
  }

  @Test func labels() {
    #expect(PlaybackSpeed.slow.label == "x0.5")
    #expect(PlaybackSpeed.normal.label == "x1")
    #expect(PlaybackSpeed.fast.label == "x1.5")
    #expect(PlaybackSpeed.instant.label == "Max")
  }

  @Test func multiplierValues() {
    // Replay-side scaling. `.instant` returns `.infinity` as a sentinel
    // — every consumer special-cases `.instant` with an explicit
    // early-return, so the sentinel is defense-in-depth, not the
    // load-bearing path.
    #expect(PlaybackSpeed.slow.multiplier == 0.5)
    #expect(PlaybackSpeed.normal.multiplier == 1.0)
    #expect(PlaybackSpeed.fast.multiplier == 1.5)
    #expect(PlaybackSpeed.instant.multiplier == .infinity)
  }
}
