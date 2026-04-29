import Foundation
import Testing

@testable import Pastura

// Tests for `PromoCard.computeEtaSeconds(currentProgress:startProgress:elapsed:)`.
//
// The helper is `nonisolated static` per ADR-009 — pure, deterministic, and
// directly testable without instantiating the View or hitting `Date()`.

@Suite("PromoCard.computeEtaSeconds", .serialized, .timeLimit(.minutes(1)))
struct PromoCardComputeEtaSecondsTests {

  // MARK: - Initial download (startProgress == 0)

  @Test("initial DL — half-progress in 60s yields ~60s remaining")
  func initialDownloadHalfProgress() {
    // 50% in 60 seconds → 0.00833 progress/sec → 50% remaining → 60 sec
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.5,
      startProgress: 0.0,
      elapsed: 60.0
    )
    #expect(seconds == 60)
  }

  @Test("initial DL — 10% in 30s yields ~270s remaining")
  func initialDownloadEarlyProgress() {
    // 10% in 30 seconds → 0.00333 progress/sec → 90% remaining → 270 sec
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.1,
      startProgress: 0.0,
      elapsed: 30.0
    )
    #expect(seconds == 270)
  }

  // MARK: - Resume after error (startProgress > 0)

  @Test(
    "resume from 50% — 1% delta in 2s yields ~98s remaining (not the broken stale-time formula)")
  func resumeFromMidpointDeltaFormula() {
    // Stale formula (BUGGY): elapsed=2s + raw progress=0.51 → total=3.92s,
    //   remaining=1.92s. Suggests download is almost done — wrong.
    // Delta formula (FIXED): progressDelta=0.01, elapsed=2s → 0.005 prog/sec.
    //   Remaining=0.49 → 98 seconds.
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.51,
      startProgress: 0.50,
      elapsed: 2.0
    )
    #expect(seconds == 98)
  }

  @Test("resume from 80% — 5% delta in 10s yields ~30s remaining")
  func resumeFromHighProgress() {
    // progressDelta=0.05 in 10s → 0.005 prog/sec → 0.15 remaining → 30 sec
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.85,
      startProgress: 0.80,
      elapsed: 10.0
    )
    #expect(seconds == 30)
  }

  // MARK: - Early-return guards

  @Test("progress delta < 0.005 returns nil (avoids divide-by-near-zero on retry start)")
  func progressDeltaTooSmallReturnsNil() {
    // Just-after-retry: progress=0.50 → 0.502 (delta=0.002), elapsed=3s.
    // Without this guard, throughput would be 0.000667/s and remaining=747s
    // — already a plausible estimate, but the math is unstable so close to
    // zero delta. Let elapsed/delta accumulate before emitting.
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.502,
      startProgress: 0.500,
      elapsed: 3.0
    )
    #expect(seconds == nil)
  }

  @Test("elapsed < 2.0s returns nil (avoids first-tick noise)")
  func elapsedTooSmallReturnsNil() {
    // First tick after retry — even if delta looks reasonable, `Date()`
    // resolution + scheduling jitter make sub-2s estimates volatile.
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.10,
      startProgress: 0.00,
      elapsed: 1.0
    )
    #expect(seconds == nil)
  }

  // MARK: - Defensive cases

  @Test("startProgress > currentProgress (negative delta) returns nil")
  func negativeDeltaReturnsNil() {
    // Should never happen in practice (progress only increases during DL),
    // but defensively handle the case rather than emit nonsense.
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.30,
      startProgress: 0.50,
      elapsed: 10.0
    )
    #expect(seconds == nil)
  }

  @Test("currentProgress == 1.0 returns 0 (download just completed)")
  func atCompletionReturnsZero() {
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 1.0,
      startProgress: 0.0,
      elapsed: 60.0
    )
    #expect(seconds == 0)
  }

  // MARK: - The reported regression

  @Test("retry scenario — 1000-min ETA bug is fixed by delta-progress + reset")
  func reportedRegressionFixed() {
    // Reported bug: original DL ran 600s (10 min) to 50%, errored. User
    // tapped Retry. Old code reused the original startDate, so on the first
    // tick after retry: elapsed=601s (since original anchor), progress=0.50,
    // total = 601 / 0.50 = 1202s, remaining = 601s = 10 min. Then progress
    // ticks up rapidly (since download resumes) and the ETA collapses fast.
    //
    // Fix: handleModelStateChange resets the anchor on `.error → .downloading`,
    // and the delta-progress formula uses (progress - startProgress) since
    // anchor instead of raw progress since unrelated original start.
    //
    // Post-fix scenario: anchor reset at retry, startProgress=0.50.
    // 5s into the retry, progress=0.51 (from URLSession resume kick-off):
    //   delta=0.01, elapsed=5 → 0.002 prog/sec → 0.49 remaining → 245 sec.
    let seconds = PromoCard.computeEtaSeconds(
      currentProgress: 0.51,
      startProgress: 0.50,
      elapsed: 5.0
    )
    #expect(seconds == 245)
  }
}
