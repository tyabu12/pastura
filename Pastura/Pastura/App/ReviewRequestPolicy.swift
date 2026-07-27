import Foundation

/// Eligibility rules for the App Store review prompt (#1279).
///
/// Split into a pure decision (``isEligible(priorCompletedRunCount:degradedTurnCount:lastRequestedVersion:currentVersion:)``)
/// and the `UserDefaults`-backed version stamp, so the decision is unit-testable
/// without touching process-wide defaults — see `.claude/rules/view-testing.md`
/// rule 1. The side-effecting half mirrors ``FeatureFlags``' accessor shape
/// (static key + read accessor + setter, read on demand with no caching).
///
/// `nonisolated` because the decision is called from both a MainActor caller
/// (``ReviewRequestCoordinator``) and nonisolated test contexts; leaving it on
/// the `App/` layer's default MainActor isolation would make the conformance
/// lookup MainActor-bound at nonisolated call sites
/// (`.claude/rules/swift-isolation.md` Pattern 5).
///
/// Deliberately **not** a sentiment gate. Routing users to the dialog based on
/// a "do you like the app?" pre-prompt violates App Store Guideline 5.6.3, so
/// the engagement thresholds below are the only filter.
nonisolated enum ReviewRequestPolicy {

  // MARK: - Thresholds

  /// Completed runs required **before** the run that just finished.
  ///
  /// Two prior runs means the just-finished run is the user's **third** — the
  /// engagement bar from #1279. The count deliberately excludes the current
  /// run because it is not reliably persisted yet at the moment the prompt
  /// fires: `SimulationViewModel.isCompleted` is set inline in the event loop,
  /// but the `status = 'completed'` row write happens later in `finalizeRun`,
  /// behind `await llm.unloadModel()` — tearing down a multi-GB GGUF is not
  /// bounded by the prompt's short delay. Counting only *prior* runs makes the
  /// threshold independent of that race, so the prompt lands on run 3 on every
  /// device rather than run 3 or 4 depending on model size.
  static let minimumPriorCompletedRuns = 2

  // MARK: - Keys

  private static let lastRequestVersionKey = "lastReviewRequestVersion"

  // MARK: - Decision

  /// Whether the review prompt may be shown for a run that just completed.
  ///
  /// All conditions must hold:
  /// - `priorCompletedRunCount >= ` ``minimumPriorCompletedRuns`` — demonstrated
  ///   engagement, per Apple's "natural and happy moment" guidance.
  /// - `degradedTurnCount == 0` — a run with skipped LLM turns (ADR-021) is a
  ///   negative-signal window; asking for a rating right after visible
  ///   degradation invites the review the prompt is meant to earn.
  /// - The current app version has not been asked before. StoreKit's own
  ///   3-per-365-days throttle is unobservable, so we record *our attempt* and
  ///   self-limit to once per released version.
  ///
  /// - Parameter currentVersion: the app's marketing version. `nil` or empty
  ///   returns `false` — without a readable version there is nothing to stamp,
  ///   so proceeding would re-ask on every completed run. Fail closed.
  static func isEligible(
    priorCompletedRunCount: Int,
    degradedTurnCount: Int,
    lastRequestedVersion: String?,
    currentVersion: String?
  ) -> Bool {
    guard let currentVersion, !currentVersion.isEmpty else { return false }
    guard priorCompletedRunCount >= minimumPriorCompletedRuns else { return false }
    guard degradedTurnCount == 0 else { return false }
    return lastRequestedVersion != currentVersion
  }

  // MARK: - Version stamp

  /// The app version the prompt was last requested for, or `nil` if never.
  static var lastRequestedVersion: String? {
    UserDefaults.standard.string(forKey: lastRequestVersionKey)
  }

  /// Records that the prompt was requested for `version`. Called on the
  /// request itself, not on any user response — StoreKit reports neither
  /// whether the dialog actually appeared nor what the user did with it.
  static func markRequested(version: String) {
    UserDefaults.standard.set(version, forKey: lastRequestVersionKey)
  }

  /// The app's marketing version (`CFBundleShortVersionString`, i.e. the
  /// `MARKETING_VERSION` build setting) — the granularity at which the prompt
  /// re-arms. Build number is deliberately not included: a TestFlight build
  /// bump should not re-open the prompt for the same released version.
  static var currentVersion: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }
}
