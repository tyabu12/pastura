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
/// ## Metric: database size only
///
/// ADR-015 D1 permits "run count **or** total DB size"; #565 picks **size
/// only**. Per-run storage is dominated by two heavy columns
/// (`turns.rawOutput`, `simulations.stateJSON` — ADR-015 §2), so total
/// byte size tracks growth directly without a separate run-count accessor.
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
  /// Database byte size at or above which the advisory surfaces. 250 MB.
  static let advisoryByteThreshold: Int64 = 250 * 1024 * 1024

  /// Whether the advisory should surface for the given database size.
  ///
  /// - Parameter databaseByteCount: Logical DB size in bytes, from
  ///   ``SimulationRepository/databaseByteCount()``.
  /// - Returns: `true` once the size reaches ``advisoryByteThreshold``.
  static func isOverAdvisoryCap(databaseByteCount: Int64) -> Bool {
    databaseByteCount >= advisoryByteThreshold
  }
}
