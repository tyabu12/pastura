import Foundation

/// Pure gating + routing logic for the failed-run resume banner (ADR-021 D8):
/// a run that ended `.failed` while holding a valid round checkpoint can be
/// resumed from the next round. Extracted so the show/hide decision and the
/// resume destination are unit-testable without rendering the View (ADR-009).
///
/// Mirrors ``DegradedRunBadge`` (the D6 completion-quality annotation); the two
/// banners are mutually exclusive by status (`.failed` here vs `.completed`
/// there), so both can live in the same timeline without ever double-rendering.
///
/// **Not `nonisolated`**: ``resumeRoute(simulationId:name:)`` builds a `Route`
/// (App-layer, default-MainActor), so the type keeps the default MainActor
/// isolation of the `Views/` layer — same as ``DegradedRunBadge``.
enum FailedRunResumeBadge {
  /// Whether the run should offer a resume affordance.
  ///
  /// True only for a `.failed` run whose `currentRound >= 1`: the round-boundary
  /// checkpoint (`stateJSON` + `currentRound`) is written together by
  /// `SimulationRepository.updateState`, so `currentRound >= 1` means round 1
  /// completed and a resumable checkpoint exists. A run that died during round 1
  /// (before any checkpoint) keeps `currentRound == 0` and is not resumable.
  /// `.completed` / `.paused` / `.running` / `.cancelled` (and a `nil` status)
  /// never offer resume here — `.paused` has its own Home resume card
  /// (``HomePausedCard``).
  static func isResumable(status: SimulationStatus?, currentRound: Int) -> Bool {
    status == .failed && currentRound >= 1
  }

  /// The resume destination for the failed run — the same route the Home
  /// paused-run card uses (``HomePausedCard/resumeRoute(for:)``). Identity is
  /// the run's id; `name` rides along as an identity-neutral `RouteHint` for the
  /// nav title from the first frame (ADR-008), so it never perturbs
  /// `pushIfOnTop` dedup.
  static func resumeRoute(simulationId: String, name: String?) -> Route {
    .resumeSimulation(simulationId: simulationId, initialName: .init(name))
  }

  /// The 1-based round the resume re-enters. The checkpoint's `currentRound` is
  /// the just-completed round K (the producer emits `.roundCheckpoint` only
  /// after `.roundCompleted`), so resume starts at K+1 — matching
  /// `SimulationViewModel.resume`.
  static func resumeRoundLabel(currentRound: Int) -> Int {
    currentRound + 1
  }
}
