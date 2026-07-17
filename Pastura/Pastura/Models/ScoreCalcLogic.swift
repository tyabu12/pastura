import Foundation

/// Identifier for a built-in scoring logic used by `score_calc` phases.
///
/// The actual implementations live in `Engine/ScoringLogic/`. Custom
/// (author-supplied) logic is Phase 2 scope. This enum is the single source of
/// truth for the built-in set; the web format spec is grep-gated against it
/// (`scripts/check-scenario-format-coverage.py`).
nonisolated public enum ScoreCalcLogic: String, Codable, Sendable, CaseIterable {
  /// Prisoner's dilemma payoff matrix.
  /// cooperate/cooperate = 3,3 | cooperate/betray = 0,5 | betray/betray = 1,1
  case prisonersDilemma = "prisoners_dilemma"

  /// Count votes per agent and add to scores.
  case voteTally = "vote_tally"

  /// Check if the most-voted agent matches the minority (word wolf) agent.
  case wordwolfJudge = "wordwolf_judge"

  /// Reward agents whose last `choose` action matched the injected event's
  /// favored action. Deterministic, code-enforced event-conditional scoring
  /// for `choose` games — decouples "who read the event best" from an LLM
  /// peer vote (the local judge's conservative prior never credits a bold
  /// read). See `EventReactivePayoffLogic` and #931.
  case eventReactive = "event_reactive"

  /// Generic two-player payoff table authored in scenario YAML (`payoff:`),
  /// matched positionally against a round-robin `choose`'s pairings. Supersedes
  /// the hardcoded matrix of ``prisonersDilemma`` (kept as a legacy shim) and
  /// unblocks localized option tokens + chicken / stag-hunt variants with no
  /// engine change. See `PairwisePayoffLogic`, `PayoffRule`, and ADR-027.
  case pairwisePayoff = "pairwise_payoff"
}
