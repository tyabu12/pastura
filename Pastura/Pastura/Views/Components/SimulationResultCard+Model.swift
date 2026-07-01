import Foundation

extension SimulationResultCard {
  /// Display-ready outcome for the card. The failable initializer is the
  /// visibility guard: a run with nothing worth showing (a pure discussion /
  /// summary, no scores / votes / eliminations) yields `nil` so the caller
  /// renders no card — mirroring ``ScenarioIntroCard/Model``'s empty-premise
  /// guard.
  ///
  /// Split into this sibling file (Apple's `Type+Feature.swift` convention) to
  /// keep `SimulationResultCard`'s type body under swiftlint's limit; declared
  /// `nonisolated` so the pure derivation runs off the MainActor and is
  /// unit-testable from a nonisolated test.
  nonisolated struct Model: Equatable {
    let framing: Framing
    let entries: [Entry]

    /// Resolves the outcome from the ViewModel's accumulated result state.
    ///
    /// Classification is **survival-primary**: an `.eliminate` phase makes
    /// survival the framing even when scores are also present (Werewolf), per
    /// the #868 product decision. `scores` is seeded with every persona at `0`
    /// at run start, so "are there scores worth ranking" is decided by *any
    /// non-zero* value (`hasScores`) — never `!scores.isEmpty`.
    ///
    /// - Parameters:
    ///   - scores: agent → cumulative score (all-zero until a scoring phase).
    ///   - eliminated: agent → eliminated flag.
    ///   - voteResults: latest vote-phase tallies (agent → votes received),
    ///     used only to rank a vote-only scenario that eliminates nobody.
    ///   - eliminationVotes: agent → vote count captured at its elimination.
    ///   - phases: the scenario's phases, inspected for `.eliminate` /
    ///     round-robin `.choose` / prisoner's-dilemma `.scoreCalc`.
    init?(
      scores: [String: Int],
      eliminated: [String: Bool],
      voteResults: [String: Int],
      eliminationVotes: [String: Int],
      phases: [Phase]
    ) {
      guard
        let resolved = Self.resolve(
          scores: scores, eliminated: eliminated, voteResults: voteResults,
          eliminationVotes: eliminationVotes, phases: phases)
      else { return nil }
      self.framing = resolved.framing
      self.entries = resolved.entries
    }

    private static func resolve(
      scores: [String: Int],
      eliminated: [String: Bool],
      voteResults: [String: Int],
      eliminationVotes: [String: Int],
      phases: [Phase]
    ) -> (framing: Framing, entries: [Entry])? {
      let phaseTypes = Set(phases.map(\.type))
      let hasScores = scores.values.contains { $0 != 0 }
      // scores/eliminated are seeded with every persona at run start, so either
      // key set is the full roster; prefer scores, fall back to eliminated.
      let roster = scores.isEmpty ? Array(eliminated.keys) : Array(scores.keys)

      // 1. Survival — an elimination phase makes "who's left" the outcome, even
      //    when scores are also present.
      if phaseTypes.contains(.eliminate) {
        guard !roster.isEmpty else { return nil }
        return (
          .survival,
          survivalEntries(
            roster: roster, eliminated: eliminated, scores: scores,
            hasScores: hasScores, eliminationVotes: eliminationVotes)
        )
      }

      // 2. Pairing — round-robin choose or a prisoner's-dilemma scoring.
      let isPairing =
        phases.contains { $0.type == .choose && $0.pairing == .roundRobin }
        || phases.contains { $0.type == .scoreCalc && $0.logic == .prisonersDilemma }
      if isPairing, hasScores {
        return (.pairing, rankedByScore(roster: roster, scores: scores, eliminated: eliminated))
      }

      // 3. Ranking — any real scoring.
      if hasScores {
        return (.ranking, rankedByScore(roster: roster, scores: scores, eliminated: eliminated))
      }

      // 4. Vote-only "popularity vote" — a vote happened but nobody was
      //    eliminated and nothing scored. Rank by votes received.
      if !voteResults.isEmpty, !roster.isEmpty {
        return (
          .ranking, rankedByVotes(roster: roster, votes: voteResults, eliminated: eliminated)
        )
      }

      // 5. Nothing worth showing (discussion / summary only).
      return nil
    }

    /// Sorts by `value` descending, then by name ascending as a deterministic
    /// tiebreak so a top tie never picks a run-to-run-unstable "winner".
    private static func ranked(
      roster: [String], value: (String) -> Int, eliminated: [String: Bool],
      valueKind: ValueKind
    ) -> [Entry] {
      let sorted = roster.sorted { lhs, rhs in
        let lhsValue = value(lhs)
        let rhsValue = value(rhs)
        return lhsValue != rhsValue ? lhsValue > rhsValue : lhs < rhs
      }
      return sorted.enumerated().map { index, name in
        Entry(
          id: name, name: name, rank: index + 1,
          isEliminated: eliminated[name] ?? false,
          primaryValue: value(name), valueKind: valueKind)
      }
    }

    private static func rankedByScore(
      roster: [String], scores: [String: Int], eliminated: [String: Bool]
    ) -> [Entry] {
      ranked(roster: roster, value: { scores[$0] ?? 0 }, eliminated: eliminated, valueKind: .points)
    }

    private static func rankedByVotes(
      roster: [String], votes: [String: Int], eliminated: [String: Bool]
    ) -> [Entry] {
      ranked(roster: roster, value: { votes[$0] ?? 0 }, eliminated: eliminated, valueKind: .votes)
    }

    /// Survivors first, then eliminated — each group deterministically ordered.
    /// With scores present (Werewolf / score-driven elimination) every row
    /// shows its score; otherwise eliminated rows show their own elimination
    /// vote count and survivors show no number.
    private static func survivalEntries(
      roster: [String], eliminated: [String: Bool], scores: [String: Int],
      hasScores: Bool, eliminationVotes: [String: Int]
    ) -> [Entry] {
      func isEliminated(_ name: String) -> Bool { eliminated[name] ?? false }

      func order(_ names: [String]) -> [String] {
        names.sorted { lhs, rhs in
          let lhsValue = hasScores ? (scores[lhs] ?? 0) : (eliminationVotes[lhs] ?? 0)
          let rhsValue = hasScores ? (scores[rhs] ?? 0) : (eliminationVotes[rhs] ?? 0)
          return lhsValue != rhsValue ? lhsValue > rhsValue : lhs < rhs
        }
      }

      func makeEntry(_ name: String) -> Entry {
        if hasScores {
          return Entry(
            id: name, name: name, rank: nil, isEliminated: isEliminated(name),
            primaryValue: scores[name] ?? 0, valueKind: .points)
        }
        if isEliminated(name) {
          let votes = eliminationVotes[name]
          return Entry(
            id: name, name: name, rank: nil, isEliminated: true,
            primaryValue: votes, valueKind: votes != nil ? .votes : .none)
        }
        return Entry(
          id: name, name: name, rank: nil, isEliminated: false,
          primaryValue: nil, valueKind: .none)
      }

      let survivors = order(roster.filter { !isEliminated($0) })
      let eliminatedAgents = order(roster.filter { isEliminated($0) })
      return (survivors + eliminatedAgents).map(makeEntry)
    }
  }
}
