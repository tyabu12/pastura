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

  @Test func readingDwellDenseValuesPinned() {
    // Change-detector pin on the dense-script (ja) reading-pause formula
    // `min(base + perChar * max(0, len), cap)`. A failure means a
    // code-review-gated pacing constant drifted — confirm it was an
    // intentional, reviewed change, then update the expected value.
    // normal dense: base 300, perChar 60 (Ren'Py afm_time=15 anchor)
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 0, script: .dense) == .milliseconds(300))
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 40, script: .dense) == .milliseconds(2700))
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 100, script: .dense) == .milliseconds(6300))
    // slow dense: base 400, perChar 80
    #expect(PlaybackSpeed.slow.readingDwell(displayLength: 0, script: .dense) == .milliseconds(400))
    #expect(
      PlaybackSpeed.slow.readingDwell(displayLength: 50, script: .dense) == .milliseconds(4400))
    // fast dense: base 200, perChar 40
    #expect(PlaybackSpeed.fast.readingDwell(displayLength: 0, script: .dense) == .milliseconds(200))
    #expect(
      PlaybackSpeed.fast.readingDwell(displayLength: 100, script: .dense) == .milliseconds(4200))
  }

  @Test func readingDwellSparseValuesPinned() {
    // sparse (en) ≈ 0.62× dense per-char; base/cap language-neutral.
    // normal sparse: base 300, perChar 38
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 0, script: .sparse) == .milliseconds(300))
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 40, script: .sparse) == .milliseconds(1820))
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 100, script: .sparse) == .milliseconds(4100))
    // slow sparse: base 400, perChar 50
    #expect(
      PlaybackSpeed.slow.readingDwell(displayLength: 100, script: .sparse) == .milliseconds(5400))
    // fast sparse: base 200, perChar 24
    #expect(
      PlaybackSpeed.fast.readingDwell(displayLength: 100, script: .sparse) == .milliseconds(2600))
  }

  @Test func readingDwellDenseExceedsSparse() {
    // Same tier + length: dense (ja) dwells longer than sparse (en).
    for speed in [PlaybackSpeed.slow, .normal, .fast] {
      let dense = speed.readingDwell(displayLength: 60, script: .dense)
      let sparse = speed.readingDwell(displayLength: 60, script: .sparse)
      #expect(dense > sparse)
    }
  }

  @Test func readingDwellInstantIsZero() {
    // Max playback keeps its no-gap behavior at any length / script.
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 0, script: .dense) == .zero)
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 100, script: .dense) == .zero)
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 100, script: .sparse) == .zero)
    #expect(PlaybackSpeed.instant.readingDwell(displayLength: 10_000, script: .dense) == .zero)
  }

  @Test func readingDwellClampsLongLines() {
    // A very long line cannot stall playback (or the cancellation window)
    // past the per-tier cap (language-neutral cap).
    #expect(
      PlaybackSpeed.slow.readingDwell(displayLength: 10_000, script: .dense) == .milliseconds(8000))
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: 10_000, script: .dense)
        == .milliseconds(6500))
    #expect(
      PlaybackSpeed.fast.readingDwell(displayLength: 10_000, script: .sparse) == .milliseconds(5000)
    )
  }

  @Test func readingDwellMonotonicAcrossTiers() {
    // Slower tier ⇒ longer (or equal) pause at a fixed length; instant is
    // always the shortest (zero).
    let len = 60
    let slow = PlaybackSpeed.slow.readingDwell(displayLength: len, script: .dense)
    let normal = PlaybackSpeed.normal.readingDwell(displayLength: len, script: .dense)
    let fast = PlaybackSpeed.fast.readingDwell(displayLength: len, script: .dense)
    let instant = PlaybackSpeed.instant.readingDwell(displayLength: len, script: .dense)
    #expect(slow >= normal)
    #expect(normal >= fast)
    #expect(fast >= instant)
    #expect(instant == .zero)
  }

  @Test func readingDwellNegativeLengthClampsToBase() {
    // Defensive: a negative length floors to 0 → base-only pause, never
    // a negative Duration.
    #expect(
      PlaybackSpeed.normal.readingDwell(displayLength: -5, script: .dense) == .milliseconds(300))
  }

  @Test func readingScriptResolvesByEngineLanguage() {
    // Only `ja` is dense today; `en` and any unknown fall back to sparse.
    #expect(ReadingScript.resolve(engineLanguage: "ja") == .dense)
    #expect(ReadingScript.resolve(engineLanguage: "en") == .sparse)
    #expect(ReadingScript.resolve(engineLanguage: "fr") == .sparse)
    #expect(ReadingScript.resolve(engineLanguage: "") == .sparse)
  }
}
