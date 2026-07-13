import Foundation

/// Reconstructs the live ``LogEntry`` stream for a resumed simulation from its
/// persisted history.
///
/// Maps each ``ResultDetailTimelineBuilder/Item`` — already merge-sorted by
/// `sequenceNumber` with round separators inserted — to the display
/// ``LogEntry`` shape `SimulationView` renders, reusing the same
/// ``ResultDetailTimelineBuilder`` the past-results viewer uses so the resumed
/// log and the past-results timeline stay structurally identical.
///
/// **Display-only.** The produced entries populate `logEntries` for visual
/// continuity but do NOT drive `currentRound` / `scores` — those are rehydrated
/// directly from the persisted `SimulationState` in
/// `SimulationViewModel.resume(record:scenario:llm:)`. Re-routing replay through
/// `handleEvent` would double-count scores and clobber the rehydrated round, so
/// the mapper deliberately bypasses it.
enum ResumeLogReplayMapper {
  /// - Parameters:
  ///   - items: Builder output for the surviving (round ≤ K) records.
  ///   - totalRounds: Scenario round count, used to fill the `.roundStarted`
  ///     total — `.roundSeparator` carries only the round number.
  ///   - contentFilter: Applied to agent output to match the App Store content
  ///     parity the live `.agentOutput` path applies at commit.
  static func map(
    items: [ResultDetailTimelineBuilder.Item],
    totalRounds: Int,
    contentFilter: ContentFilter
  ) -> [LogEntry] {
    items.compactMap { item in
      switch item {
      case .roundSeparator(let round):
        return LogEntry(kind: .roundStarted(round: round, totalRounds: totalRounds))
      case .turn(let record):
        // Pre-#92 records without agentName / unparseable phaseType are legacy
        // and have no live-log representation; resumed runs only carry v6+
        // records, so dropping these is a defensive no-op in practice.
        guard let agentName = record.agentName,
          let phaseType = PhaseType(rawValue: record.phaseType)
        else { return nil }
        // `parsedOutputJSON` is persisted unfiltered; `decodeFiltered` applies
        // ContentFilter at read time (ADR-005 §5.1), single-sourcing the
        // invariant with the past-results viewer (#1075).
        return LogEntry(
          kind: .agentOutput(
            agent: agentName,
            output: PersistedTurnDecoder.decodeFiltered(
              record, contentFilter: contentFilter),
            phaseType: phaseType))
      case .codePhase(_, let payload):
        return LogEntry(kind: logEntryKind(for: payload))
      }
    }
  }

  /// Maps a decoded ``CodePhaseEventPayload`` to its display ``LogEntry/Kind``.
  /// One-to-one with the live `handleOutputEvent` dispatch so a replayed
  /// code-phase row renders identically to its original live row.
  private static func logEntryKind(for payload: CodePhaseEventPayload) -> LogEntry.Kind {
    switch payload {
    case .elimination(let agent, let voteCount):
      return .elimination(agent: agent, voteCount: voteCount)
    case .scoreUpdate(let scores):
      return .scoreUpdate(scores: scores)
    case .summary(let text):
      return .summary(text: text)
    case .narration(let text):
      return .narration(text: text)
    case .voteResults(let votes, let tallies):
      return .voteResults(votes: votes, tallies: tallies)
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      return .pairingResult(
        agent1: agent1, action1: action1, agent2: agent2, action2: action2)
    case .assignment(let agent, let value):
      return .assignment(agent: agent, value: value)
    case .sharedAssignment(let value):
      return .sharedAssignment(value: value)
    case .eventInjected(let event):
      return .eventInjected(event: event)
    }
  }
}
