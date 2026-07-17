import Foundation

/// Prisoner's dilemma scoring logic — a **legacy shim** over
/// `PairwisePayoffLogic` (ADR-027).
///
/// This case is kept indefinitely, NOT because prisoner's dilemma is special,
/// but because a user's "Copy & Edit" clone on a shipped device may carry
/// `logic: prisoners_dilemma` in its saved YAML; deleting the case would make
/// that record unopenable (ADR-027 § "Why the legacy case cannot be retired").
/// New scenarios should use `pairwise_payoff` with a YAML `payoff:` table.
///
/// The shim hands `PairwisePayoffLogic` the fixed English payoff table below.
/// That table is the game's rule set — it must **not** be trimmed: dropping the
/// `[betray, betray] → [1, 1]` row would score mutual defection as 0 in shipped
/// TestFlight content (ADR-027 § "What it shrinks to").
nonisolated struct PrisonersDilemmaLogic: Sendable {

  /// The legacy prisoner's-dilemma payoff matrix. Exhaustive over
  /// `{cooperate, betray}²`, so for all shipped content every pairing matches a
  /// row — the shim is behaviourally identical to the pre-ADR-027 hardcoded
  /// `switch` for every reachable action pair.
  static let legacyTable: [PayoffRule] = [
    PayoffRule(when: ["cooperate", "cooperate"], points: [3, 3]),
    PayoffRule(when: ["cooperate", "betray"], points: [0, 5]),
    PayoffRule(when: ["betray", "cooperate"], points: [5, 0]),
    PayoffRule(when: ["betray", "betray"], points: [1, 1])
  ]

  func calculate(
    state: inout SimulationState,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    PairwisePayoffLogic().calculate(
      state: &state, payoff: Self.legacyTable, emitter: emitter)
  }
}
