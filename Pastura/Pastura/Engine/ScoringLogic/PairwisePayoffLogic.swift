import Foundation

/// Generic pairwise payoff scoring logic (ADR-027).
///
/// Scores each `Pairing` by matching `(action1, action2)` positionally against
/// a YAML-authored payoff table (`[PayoffRule]`). The first row whose `when`
/// equals the pairing's two actions awards `points[0]` to `agent1` and
/// `points[1]` to `agent2`. A pairing matching no row scores nothing — the
/// engine never fabricates a verdict (a `nil` action, an off-table action
/// pair, or an empty table all degrade to zero, per ADR-027 § "Dead code
/// removed in passing").
///
/// Mirrors the YAML-authored-token shape of `EventReactivePayoffLogic` (#931):
/// no option literal is hardcoded here, so localized tokens (`[協力, 裏切り]`)
/// and chicken / stag-hunt tables score with no engine change. Clears
/// `state.pairings` after scoring, exactly as the legacy `PrisonersDilemmaLogic`
/// shim does.
nonisolated struct PairwisePayoffLogic: Sendable {

  func calculate(
    state: inout SimulationState,
    payoff: [PayoffRule],
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    for pairing in state.pairings {
      guard let act1 = pairing.action1, let act2 = pairing.action2 else {
        // A half-real pairing (either action nil) matches no row and scores
        // nothing — the correct degradation, not a fabricated verdict.
        continue
      }
      guard let row = payoff.first(where: { $0.when == [act1, act2] }),
        row.points.count == 2
      else {
        // No row for this action pair (or a malformed row that slipped past
        // the loader's arity guard) → score nothing.
        continue
      }
      state.scores[pairing.agent1, default: 0] += row.points[0]
      state.scores[pairing.agent2, default: 0] += row.points[1]
    }

    emitter(.scoreUpdate(scores: state.scores))
    state.pairings = []
  }
}
