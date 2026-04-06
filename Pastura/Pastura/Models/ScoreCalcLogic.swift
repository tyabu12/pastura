import Foundation

/// Identifier for a built-in scoring logic used by `score_calc` phases.
///
/// MVP includes exactly 3 scoring logics. The actual implementations
/// live in `Engine/ScoringLogic/`. Custom logic is Phase 2 scope.
public enum ScoreCalcLogic: String, Codable, Sendable, CaseIterable {
  /// Prisoner's dilemma payoff matrix.
  /// cooperate/cooperate = 3,3 | cooperate/betray = 0,5 | betray/betray = 1,1
  case prisonersDilemma = "prisoners_dilemma"

  /// Count votes per agent and add to scores.
  case voteTally = "vote_tally"

  /// Check if the most-voted agent matches the minority (word wolf) agent.
  case wordwolfJudge = "wordwolf_judge"
}
