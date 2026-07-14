import Foundation

/// The reason a live agent utterance was surfaced as a share-highlight
/// candidate at simulation end (#1070 Stage 2). Drives the reason chip on
/// each candidate row.
///
/// `nonisolated` so it can be constructed and returned from the nonisolated
/// selection logic below under default-MainActor isolation (a MainActor
/// `init` would be unreachable from a nonisolated sync context), which also
/// releases its `Equatable` conformance for nonisolated / test call sites
/// (swift-isolation Pattern 5).
nonisolated enum HighlightReason: Equatable, Sendable {
  /// The agent's public `declared_intent` was contradicted by all of their
  /// choose actions that round (🃏, #916).
  case contradiction
  /// The agent was the ground-truth answer to the run's viewer-prediction
  /// question — the wolf or the top vote-getter — revealed at vote time
  /// (🎯, #915). Surfaced whether or not the viewer guessed correctly: the
  /// reveal itself is the shareable moment.
  case revealed
}

/// Pure selection logic for automatic share-highlight candidates (#1070
/// Stage 2).
///
/// The ViewModel owns transcript assembly and card construction; this enum
/// owns the single decision: given the run's ordered agent-output entries
/// plus the two zero-inference signals (contradiction badges, prediction
/// reveal), which entries — in what order, capped — become share candidates
/// and why. Kept `nonisolated` and dependency-free (Foundation + the Models
/// `PhaseType` only, never the App-layer `LogEntry`) so it unit-tests off
/// the MainActor without rendering a View (ADR-009 /
/// `.claude/rules/view-testing.md`).
nonisolated enum HighlightCandidateLogic {

  /// A single agent-output entry in transcript order, projected to just the
  /// fields the selection needs. The caller maps `LogEntry.agentOutput`
  /// entries to these (`id` = the `LogEntry` id), preserving run order.
  nonisolated struct Entry: Equatable, Sendable {
    let id: UUID
    let agent: String
    let phaseType: PhaseType
    /// Whether this entry carries a 🃏 contradiction badge
    /// (`SimulationViewModel.contradictionBadgedEntryIDs`).
    let isContradiction: Bool
  }

  /// One selected candidate: the source entry id and why it was surfaced.
  nonisolated struct Selection: Equatable, Sendable {
    let id: UUID
    let reason: HighlightReason
  }

  /// Default cap on surfaced candidates — keeps the end-of-run section from
  /// becoming a wall of cards.
  static let defaultLimit = 3

  /// Selects share-highlight candidates from `entries` (agent outputs in
  /// transcript order).
  ///
  /// - Contradiction: every entry with `isContradiction == true` becomes a
  ///   candidate (reason `.contradiction`).
  /// - Reveal: when `actualAgent` is non-nil (a prediction was scored this
  ///   run), that agent's *last* speak-phase entry becomes a candidate
  ///   (reason `.revealed`). Speak phases are `.speakAll` / `.speakEach` —
  ///   the phases whose primary output is a public statement worth quoting;
  ///   an agent that only voted (or never spoke) yields no reveal candidate.
  ///
  /// De-dup is by entry id with contradiction winning: if the reveal entry
  /// is already a contradiction candidate it keeps the `.contradiction`
  /// reason (the stronger signal) rather than appearing twice. Output stays
  /// in transcript order and is capped at `limit`; because contradictions
  /// are emitted in order and the reveal is chronologically the agent's last
  /// statement, a run with `limit` contradictions can evict the reveal.
  static func candidates(
    entries: [Entry],
    actualAgent: String?,
    limit: Int = defaultLimit
  ) -> [Selection] {
    // The reveal entry: the actual agent's last speak-phase output.
    let revealID: UUID? = actualAgent.flatMap { agent in
      entries.last { $0.agent == agent && isSpeakPhase($0.phaseType) }?.id
    }

    var result: [Selection] = []
    for entry in entries {
      let reason: HighlightReason?
      if entry.isContradiction {
        reason = .contradiction  // contradiction wins the de-dup
      } else if entry.id == revealID {
        reason = .revealed
      } else {
        reason = nil
      }
      guard let reason else { continue }
      result.append(Selection(id: entry.id, reason: reason))
      if result.count >= limit { break }
    }
    return result
  }

  /// The speak phases whose primary output is a public statement worth
  /// quoting on a card. Inlined here (not a `PhaseType` helper) to keep the
  /// change App-only — Models must not gain a member for this feature.
  private static func isSpeakPhase(_ phaseType: PhaseType) -> Bool {
    phaseType == .speakAll || phaseType == .speakEach
  }
}
