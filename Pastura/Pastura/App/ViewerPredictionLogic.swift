import Foundation

/// Pure, off-main decision logic for the viewer-prediction feature (#915).
///
/// The ViewModel owns event interception and DB persistence; this enum owns
/// the *decisions*: which question a scenario invites, and — computed at the
/// vote-reveal moment from data already in hand, never from the completion-time
/// result card — the ground-truth answer. Kept `nonisolated` and dependency-free
/// (Models only) so it unit-tests off the MainActor without rendering a View
/// (ADR-009 / `.claude/rules/view-testing.md`).
nonisolated enum ViewerPredictionLogic {

  /// The prediction a scenario invites.
  enum Question: String, Equatable, Sendable {
    /// "Who is the wolf?" — scored against the minority-word holder.
    case wolf
    /// "Who is #1?" — scored against the top vote-getter.
    case topVote
  }

  /// Classifies a scenario into a prediction question, or `nil` when it isn't
  /// prediction-shaped. Wolf takes priority: a word-wolf scenario has both a
  /// `random_one` assign and a `vote`, and the wolf-guess is the sharper
  /// question. Scenarios with neither a `random_one` assign nor a `vote`
  /// (e.g. prisoner's-dilemma `choose` scenarios) invite no prediction, so the
  /// sheet never interrupts them.
  static func question(for phases: [Phase]) -> Question? {
    let all = flattened(phases)
    if all.contains(where: { $0.type == .assign && $0.target == .randomOne }) {
      return .wolf
    }
    if all.contains(where: { $0.type == .vote }) {
      return .topVote
    }
    return nil
  }

  /// Ground truth for `.wolf`: the sole holder of the minority (rarest) value
  /// among `assignments` (agent → assigned value). Returns `nil` when the
  /// minority is not uniquely determined — a 2-agent 1-vs-1 split, two values
  /// tied for rarest, or a rarest value shared by several agents — so the run
  /// is left unscored rather than mis-scored.
  static func wolf(from assignments: [String: String]) -> String? {
    guard !assignments.isEmpty else { return nil }
    var frequency: [String: Int] = [:]
    for value in assignments.values { frequency[value, default: 0] += 1 }
    guard let minCount = frequency.values.min() else { return nil }
    let rarestValues = frequency.filter { $0.value == minCount }.map(\.key)
    guard rarestValues.count == 1, let minorityValue = rarestValues.first else {
      return nil
    }
    let holders = assignments.filter { $0.value == minorityValue }.map(\.key)
    guard holders.count == 1 else { return nil }
    return holders.first
  }

  /// Ground truth for `.topVote`: the #1 vote-getter among `roster`, using the
  /// same tiebreak the result card uses (`RankingOrder`) so the accuracy badge
  /// and the displayed #1 can never disagree. `nil` when `roster` is empty.
  static func topVote(tallies: [String: Int], roster: [String]) -> String? {
    RankingOrder.leader(values: tallies, among: roster)
  }

  /// Whether the viewer's pick matched the ground-truth agent.
  static func isHit(predicted: String, actual: String) -> Bool {
    predicted == actual
  }

  /// Flattens depth-1 conditional branches so a `vote` / `assign` nested inside
  /// a `conditional` still classifies (the engine caps conditional nesting at
  /// depth 1, so a single non-recursive expansion is exhaustive).
  private static func flattened(_ phases: [Phase]) -> [Phase] {
    phases.flatMap { phase in
      [phase] + (phase.thenPhases ?? []) + (phase.elsePhases ?? [])
    }
  }
}
