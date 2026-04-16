import Testing

@testable import Pastura

@MainActor
struct PlaybackSpeedTests {
  @Test func allCasesEnumerated() {
    #expect(PlaybackSpeed.allCases == [.normal, .fast, .instant])
  }

  @Test func charsPerSecondValues() {
    #expect(PlaybackSpeed.normal.charsPerSecond == 40)
    #expect(PlaybackSpeed.fast.charsPerSecond == 80)
    #expect(PlaybackSpeed.instant.charsPerSecond == nil)
  }

  @Test func interEventDelayMsValues() {
    // Paced speeds share a small delay so round/phase transitions remain
    // perceptible; instant skips pacing entirely.
    #expect(PlaybackSpeed.normal.interEventDelayMs == 120)
    #expect(PlaybackSpeed.fast.interEventDelayMs == 120)
    #expect(PlaybackSpeed.instant.interEventDelayMs == 0)
  }

  @Test func labels() {
    #expect(PlaybackSpeed.normal.label == "Normal")
    #expect(PlaybackSpeed.fast.label == "Fast")
    #expect(PlaybackSpeed.instant.label == "Instant")
  }
}
