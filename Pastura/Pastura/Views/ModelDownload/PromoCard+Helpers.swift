import Foundation

// MARK: - Pure helpers (testable)
//
// Lifted out of the main struct body — and now out of `PromoCard.swift` itself
// — to keep both `type_body_length` and `file_length` under cap. They are
// `nonisolated static` so accessing them as `PromoCard.computeSlotState(...)`
// from the View remains source-compatible.
extension PromoCard {

  /// Computes the next slot rotation state from the current accumulator,
  /// the last foreground anchor, and the current time. All inputs are
  /// explicit so the caller can unit-test wrap-around, BG pauses, and
  /// resume continuity without `@State` or a live clock.
  nonisolated static func computeSlotState(
    previousSlot: Int,
    foregroundElapsed: TimeInterval,
    lastAnchor: Date?,
    now: Date,
    slotDuration: TimeInterval
  ) -> SlotRotationState {
    let inflight = lastAnchor.map { now.timeIntervalSince($0) } ?? 0
    let totalInSlot = foregroundElapsed + inflight
    if totalInSlot >= slotDuration {
      // Slot advances; accumulator resets. The anchor only advances to `now`
      // when foregrounded (nil anchor means BG and stays nil).
      return SlotRotationState(
        slot: (previousSlot + 1) % 3,
        foregroundElapsed: 0,
        lastAnchor: lastAnchor == nil ? nil : now)
    }
    return SlotRotationState(
      slot: previousSlot,
      foregroundElapsed: foregroundElapsed,
      lastAnchor: lastAnchor)
  }

  /// Return value of ``computeSlotState(previousSlot:foregroundElapsed:lastAnchor:now:slotDuration:)``.
  ///
  /// Explicitly `nonisolated` so the pure rotation math is testable from a
  /// nonisolated test suite without hopping the main actor.
  nonisolated struct SlotRotationState: Equatable, Sendable {
    let slot: Int
    let foregroundElapsed: TimeInterval
    let lastAnchor: Date?
  }

  /// Slot copy (draft) from `docs/design/design-system.md` §7.
  /// Final wording is gated on the copy pass per spec §2 decision 13.
  static func slotCopy(_ slot: Int) -> String {
    switch slot % 3 {
    case 0: return "AIエージェントが、あなたのiPhoneの中で対話します"
    case 1: return "少しだけお待ちください。その間、他のエージェントたちの様子をどうぞ"
    default: return "このアプリは広告もログインもなく、あなたの端末だけで静かに動きます"
    }
  }

  /// `残り約N分` when minutes > 0, `まもなく` when <= 0, nil to hide.
  static func formatEta(minutes: Int?) -> String? {
    guard let minutes = minutes else { return nil }
    return minutes <= 0 ? "まもなく" : "残り約\(minutes)分"
  }

  /// Computes the remaining-seconds estimate from the **delta** between current
  /// progress and the anchor progress (snapshot at `.downloading` entry), over
  /// `elapsed` seconds since the anchor was set.
  ///
  /// Why delta-progress: when a retry resumes from a non-zero offset (e.g., the
  /// `.download` file already had 50 % from a prior attempt, or `URLSession`
  /// resumed via `withResumeData`), using raw progress would treat the
  /// pre-retry bytes as if they were earned in the current `elapsed` window —
  /// inflating the throughput estimate. The delta restores the throughput
  /// to "bytes earned during this retry / time spent in this retry".
  ///
  /// Why the early-return guards:
  /// - `progressDelta < 0.005`: just after the retry begins, before the first
  ///   progress callback fires, the delta is near-zero. Without this guard the
  ///   formula would emit `まもなく` (zero-seconds remaining) prematurely.
  /// - `elapsed < 2.0 s`: same divide-by-near-zero protection on the time axis.
  ///
  /// Why BG time is not subtracted from `elapsed`: during a BG sojourn the user
  /// is not viewing the screen, and `BGContinuedProcessingTask` (ADR-003) keeps
  /// the download running, so `progressDelta` advances roughly in proportion to
  /// the BG-included `elapsed`. The ratio averages cleanly. Subtracting BG time
  /// would require a foreground-only accumulator (mirroring `foregroundElapsed`
  /// in the slot-rotation logic) and is a refinement, not a correctness fix.
  ///
  /// Returns `nil` to hide the ETA; otherwise the remaining-seconds estimate
  /// (caller divides by 60 for minute display).
  nonisolated static func computeEtaSeconds(
    currentProgress: Double,
    startProgress: Double,
    elapsed: TimeInterval
  ) -> Int? {
    let progressDelta = currentProgress - startProgress
    guard progressDelta >= 0.005, elapsed >= 2.0 else { return nil }
    let progressPerSecond = progressDelta / elapsed
    guard progressPerSecond > 0 else { return nil }
    let remainingProgress = max(0, 1.0 - currentProgress)
    let remainingSeconds = remainingProgress / progressPerSecond
    // Round-to-nearest rather than truncate — `Double` accumulates error in
    // the divisions above (e.g., 0.49 / 0.005 evaluates to 97.999… not 98.0).
    return Int(remainingSeconds.rounded())
  }
}
