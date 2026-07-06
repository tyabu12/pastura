import Foundation

/// Event-reactive payoff scoring logic.
///
/// Rewards every agent whose most recent `choose` action matched the
/// favored action for this round's injected event. The favored action is
/// read from `state.variables[favoredVariable]`, written by
/// `EventInjectHandler` for dict-shaped events (`{ text, favors }`) via the
/// `EventInjectHandler.favoredVariableName(for:)` convention.
///
/// Why code, not an LLM peer vote: the local judge model (`gemma-4-E2B`)
/// has a strong conservative prior and almost never credits a bold
/// (defection) read as "smart," so "correctly-timed boldness is rewarded"
/// could not be produced through peer judging. Moving the judge into code
/// makes a correctly-timed bold read a scarce, high-value win regardless of
/// the model's disposition. See #931.
///
/// A flat `+3` for a correct read is enough to prove the mechanic;
/// scarcity/curve bonuses and wrong-read penalties are out of scope for v1.
nonisolated struct EventReactivePayoffLogic: Sendable {

  /// Points awarded to each agent whose action matched the favored action.
  static let matchReward = 3

  func calculate(
    state: inout SimulationState,
    favoredVariable: String,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    // No favored action for this round (plain-string event list, a
    // probability miss, or an untagged dict entry) → inert no-op. The
    // empty-string check also covers the ghosting-prevention "" that
    // EventInjectHandler writes on a miss round.
    guard let favored = state.variables[favoredVariable], !favored.isEmpty else {
      emitter(.scoreUpdate(scores: state.scores))
      return
    }
    let normalizedFavored = Self.normalize(favored)

    // `state.scores[name] != nil` gates out non-agent outputs; scores are
    // seeded for every agent at `SimulationState.initial`, so a live agent
    // is always present.
    for (name, output) in state.lastOutputs where state.scores[name] != nil {
      guard let action = output.action else { continue }
      if Self.normalize(action) == normalizedFavored {
        state.scores[name, default: 0] += Self.matchReward
      }
    }

    emitter(.scoreUpdate(scores: state.scores))
  }

  /// Trim + case-fold for the action↔favored comparison. The individual
  /// (non-round-robin) `choose` path stores the LLM's raw `action` into
  /// `lastOutputs` without `ChooseHandler.validateAction` canonicalization,
  /// and `choose` no longer grammar-constrains the value to the option set
  /// (#597/#599). So the model may emit `"Betray"` / `" betray"` for a
  /// `favors: betray` round; exact `==` would under-reward a correct read.
  /// Curated `favors` values conventionally match the option casing, so
  /// symmetric fold-both-sides never over-matches.
  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
