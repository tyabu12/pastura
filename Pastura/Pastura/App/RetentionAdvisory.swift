import Foundation

/// Advisory (non-deleting) growth-cap policy for the execution-log
/// database (ADR-015 D1 / §3, issue #565).
///
/// ADR-015 decided **against** any silent auto-deletion of past runs —
/// they are the user's accumulated experiment history, the primary asset
/// of the run-to-run comparison loop. The only backstop against
/// pathological unbounded growth is this **non-silent advisory**: when the
/// store grows large, the app surfaces a prompt inviting the user to purge
/// via the existing "Clear all results" affordance (#545). It never
/// deletes without explicit consent.
///
/// ## Metric: past-results content size only
///
/// ADR-015 D1 permits "run count **or** total DB size"; #565 picks **size
/// only**. Per-run storage is dominated by two heavy columns
/// (`turns.rawOutput`, `simulations.stateJSON` — ADR-015 §2), so total
/// byte size tracks growth directly without a separate run-count accessor.
/// As of #770 the measure is the *past-results* content size
/// (``SimulationRepository/pastResultsByteCount()``), not the whole-DB file
/// size — it excludes the `scenarios` table + SQLite schema/index pages.
/// That number is strictly smaller than the old whole-DB measure, so the
/// advisory now fires *no earlier* than before for the same data; against a
/// 250 MB threshold the excluded KB-scale overhead is immaterial.
///
/// ## Threshold: 250 MB, generous by design
///
/// ADR-015 §2 estimates ~100 MB ≈ hundreds-to-~a-thousand runs, reached
/// over months given human-paced on-device inference. 250 MB is ~2.5× that
/// reference point — comfortably above any normal heavy-use regime, so the
/// advisory fires only on genuinely pathological accumulation. It is a
/// safety stop, not routine housekeeping. The number is tunable here per
/// ADR-015 D1 (the *decision* — an advisory cap exists, never auto-deletes
/// — is fixed in the ADR; only the literal lives in code).
enum RetentionAdvisory {
  /// Past-results content size at or above which the advisory surfaces. 250 MB.
  static let advisoryByteThreshold: Int64 = 250 * 1024 * 1024

  /// Whether the advisory should surface for the given past-results size.
  ///
  /// - Parameter pastResultsByteCount: Past-results content size in bytes,
  ///   from ``SimulationRepository/pastResultsByteCount()``.
  /// - Returns: `true` once the size reaches ``advisoryByteThreshold``.
  static func isOverAdvisoryCap(pastResultsByteCount: Int64) -> Bool {
    pastResultsByteCount >= advisoryByteThreshold
  }
}
