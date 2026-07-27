import Foundation
import os

/// Drives the App Store review prompt at a completed run's "happy moment"
/// (#1279): reads the engagement count, applies ``ReviewRequestPolicy``, and
/// fires the caller-supplied StoreKit request exactly once per app version.
///
/// Lives in `App/` because it spans Data (the run count) and UI (the SwiftUI
/// `requestReview` action); `App/` may depend on everything. The StoreKit
/// action itself is injected as a closure rather than imported here, so this
/// type stays free of SwiftUI and the decision path is reachable from a plain
/// caller.
///
/// MainActor-isolated by the `App/` layer default — the injected
/// `requestReview` action must be invoked on the main actor, and the only DB
/// read hops off via ``offMain(_:)``.
enum ReviewRequestCoordinator {

  private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "ReviewRequest")

  /// Requests a review if every ``ReviewRequestPolicy`` condition holds.
  ///
  /// Silent no-op otherwise — including on a DB read failure, which must never
  /// escalate: a missed prompt costs one rating, a thrown error at a run's
  /// closing moment costs the user's session.
  ///
  /// - Parameters:
  ///   - repository: source of the lifetime completed-run count.
  ///   - currentRunId: the run that just finished, excluded from the count so
  ///     the threshold does not depend on whether its `status = 'completed'`
  ///     write has landed yet. See ``ReviewRequestPolicy/minimumPriorCompletedRuns``.
  ///   - degradedTurnCount: ADR-021 skip count for the run that just finished.
  ///   - isUITestMode: injectable for tests; production callers take the
  ///     default. Under `--ui-test` the harness seeds completed runs, so the
  ///     threshold is already satisfiable — and a StoreKit modal appearing
  ///     mid-XCUITest surfaces as an element-query flake rather than a clean
  ///     failure. Same suppression rationale as `DogMark` /
  ///     `InFlightSimulationIndicator`. This is deliberately an explicit gate
  ///     rather than relying on the harness's empty mock queue incidentally
  ///     tripping the `degradedTurnCount` condition.
  ///   - currentVersion: the marketing version to stamp on success. Injectable
  ///     for tests; production callers take the `Bundle.main` default.
  ///   - defaults: store backing the version stamp. Injectable so tests drive
  ///     an isolated `UserDefaults(suiteName:)` rather than the process-wide
  ///     store.
  ///   - requestReview: the StoreKit request to fire on success. StoreKit
  ///     reports neither whether the dialog appeared nor the user's response,
  ///     so there is nothing to return.
  static func requestIfEligible(
    repository: any SimulationRepository,
    currentRunId: String?,
    degradedTurnCount: Int,
    isUITestMode: Bool = UITestMode.isActive,
    currentVersion: String? = ReviewRequestPolicy.currentVersion,
    defaults: UserDefaults = .standard,
    requestReview: () -> Void
  ) async {
    guard !isUITestMode else { return }
    // Structural, not a duplicate of the policy's own version check: we need a
    // non-nil, non-empty value to stamp on success, and unwrapping it here also
    // avoids a pointless DB read on the path where the verdict is already
    // determined. The policy re-checks so it stays correct for any caller.
    guard let currentVersion, !currentVersion.isEmpty else { return }

    let priorCompletedRunCount: Int
    do {
      priorCompletedRunCount = try await offMain {
        try repository.completedRunCount(excludingRunId: currentRunId)
      }
    } catch {
      logger.error(
        "completedRunCount failed; skipping review prompt: \(String(describing: error), privacy: .public)"
      )
      return
    }

    guard
      ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: priorCompletedRunCount,
        degradedTurnCount: degradedTurnCount,
        lastRequestedVersion: ReviewRequestPolicy.lastRequestedVersion(defaults: defaults),
        currentVersion: currentVersion)
    else { return }

    // Stamp before firing: StoreKit gives no completion signal, so a stamp
    // afterwards has no better moment to run and a crash in between would
    // re-arm the prompt for the same version.
    ReviewRequestPolicy.markRequested(version: currentVersion, defaults: defaults)
    requestReview()
  }
}
