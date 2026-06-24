import Foundation
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
    // `.slow`/`.normal`/`.fast` literal-pin guards the slice-6 carve-out
    // (universal multiplier notation never wrapped in `String(localized:)`);
    // `.instant` routes through `String(localized: "Max")` and resolves
    // via the same Bundle lookup the production code uses, so the
    // assertion stays locale-resilient.
    #expect(PlaybackSpeed.slow.label == "x0.5")
    #expect(PlaybackSpeed.normal.label == "x1")
    #expect(PlaybackSpeed.fast.label == "x1.5")
    #expect(PlaybackSpeed.instant.label == String(localized: "Max"))
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

  // MARK: - readingDwell (Sim-only VN reading pause)

  @Test func readingDwellValuesPinned() {
    // Change-detector pin on the Sim reading-pause formula
    // `min(base + perChar * max(0, len), cap)`. A failure means a
    // code-review-gated pacing constant drifted — confirm it was an
    // intentional, reviewed change, then update the expected value.
    // normal: base 350, perChar 18, cap 3200
    #expect(PlaybackSpeed.normal.readingDwell(displayLength: 0) == .milliseconds(350))
    #expect(PlaybackSpeed.normal.readingDwell(displayLength: 40) == .milliseconds(1070))
    #expect(PlaybackSpeed.normal.readingDwell(displayLength: 100) == .milliseconds(2150))
    // slow: base 500, perChar 28, cap 4500
    #expect(PlaybackSpeed.slow.readingDwell(displayLength: 0) == .milliseconds(500))
    #expect(PlaybackSpeed.slow.readingDwell(displayLength: 100) == .milliseconds(3300))
    // fast: base 220, perChar 10, cap 2200
    #expect(PlaybackSpeed.fast.readingDwell(displayLength: 0) == .milliseconds(220))
    #expect(PlaybackSpeed.fast.readingDwell(displayLength: 100) == .milliseconds(1220))
  }

  @Test func readingDwellInstantIsZero() {
    // Max playback keeps its no-gap behavior at any length.
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 0) == .zero)
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 100) == .zero)
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 10_000) == .zero)
  }

  @Test func readingDwellClampsLongLines() {
    // A very long line cannot stall playback (or the cancellation window)
    // past the per-tier cap.
    #expect(PlaybackSpeed.slow.readingDwell(displayLength: 10_000) == .milliseconds(4500))
    #expect(PlaybackSpeed.normal.readingDwell(displayLength: 10_000) == .milliseconds(3200))
    #expect(PlaybackSpeed.fast.readingDwell(displayLength: 10_000) == .milliseconds(2200))
  }

  @Test func readingDwellMonotonicAcrossTiers() {
    // Slower tier ⇒ longer (or equal) pause at a fixed length; instant is
    // always the shortest (zero).
    let len = 100
    let slow = PlaybackSpeed.slow.readingDwell(displayLength: len)
    let normal = PlaybackSpeed.normal.readingDwell(displayLength: len)
    let fast = PlaybackSpeed.fast.readingDwell(displayLength: len)
    let instant = PlaybackSpeed.instant.readingDwell(displayLength: len)
    #expect(slow >= normal)
    #expect(normal >= fast)
    #expect(fast >= instant)
    #expect(instant == .zero)
  }

  @Test func readingDwellNegativeLengthClampsToBase() {
    // Defensive: a negative length floors to 0 → base-only pause, never
    // a negative Duration.
    #expect(PlaybackSpeed.normal.readingDwell(displayLength: -5) == .milliseconds(350))
  }
}
