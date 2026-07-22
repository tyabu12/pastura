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
  /// The agent's first speak-phase utterance right after the game situation
  /// shifted — an `event_inject` firing or a `vote` reveal (💥, #1109). A
  /// positional zero-inference signal: the first to speak once "the room
  /// moved". Weaker than `.contradiction` / `.revealed` (positional, not a
  /// verified fact), so it is de-dup-superseded by either (see `candidates`).
  case reaction
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
    /// Whether this entry is the first speak-phase reaction after an event
    /// boundary (💥, #1109), as pre-computed by `reactionEntryIDs`. Defaulted
    /// so Stage-2 call sites that predate the signal stay source-compatible.
    let isReaction: Bool

    init(
      id: UUID,
      agent: String,
      phaseType: PhaseType,
      isContradiction: Bool,
      isReaction: Bool = false
    ) {
      self.id = id
      self.agent = agent
      self.phaseType = phaseType
      self.isContradiction = isContradiction
      self.isReaction = isReaction
    }
  }

  /// One selected candidate: the source entry id and why it was surfaced.
  nonisolated struct Selection: Equatable, Sendable {
    let id: UUID
    let reason: HighlightReason
  }

  /// An ordered projection of the run transcript for reaction correlation
  /// (💥, #1109): either an agent output (tagged with its phase) or a
  /// "context reset" boundary. The ViewModel builds this from the same single
  /// filtered `logEntries` walk that produces the `Entry` descriptors.
  ///
  /// `nonisolated` for the same reason as `Entry` / `Selection` (swift-isolation
  /// Pattern 5): `reactionEntryIDs` runs off the MainActor and needs the
  /// auto-synthesized `Equatable` conformance lookup released.
  nonisolated enum ReactionItem: Equatable, Sendable {
    /// An agent output in transcript order — the same entries projected to
    /// `Entry` — carrying its phase so a reaction can require a speak phase.
    case output(id: UUID, phaseType: PhaseType)
    /// "The room moved": an `event_inject` that actually fired (non-nil event)
    /// or a `vote` reveal. Arms the next speak output as a reaction.
    case eventBoundary
    /// A round start — closes the same-round window so a tail-of-round event
    /// (typically `vote`) never mis-correlates to the next round's opening
    /// speak.
    case roundBoundary
  }

  /// Default cap on surfaced candidates — keeps the end-of-run section from
  /// becoming a wall of cards.
  static let defaultLimit = 3

  /// Selects share-highlight candidates from `entries` (agent outputs in
  /// transcript order).
  ///
  /// Two-tier selection (#1109). Tier 1 is the verified/ground-truth signals,
  /// tier 2 the weaker positional one:
  ///
  /// - Contradiction: every entry with `isContradiction == true` becomes a
  ///   candidate (reason `.contradiction`).
  /// - Reveal: when `actualAgent` is non-nil (a prediction was scored this
  ///   run), that agent's *last* speak-phase entry becomes a candidate
  ///   (reason `.revealed`). Speak phases are `.speakAll` / `.speakEach` —
  ///   the phases whose primary output is a public statement worth quoting;
  ///   an agent that only voted (or never spoke) yields no reveal candidate.
  /// - Reaction: every entry with `isReaction == true` (pre-computed by
  ///   `reactionEntryIDs`) can become a candidate (reason `.reaction`), but
  ///   **only fills slots the tier-1 signals left free** — it never displaces
  ///   a contradiction or reveal.
  ///
  /// De-dup is by entry id with the stronger signal winning: a reveal or
  /// reaction entry already chosen as a contradiction keeps `.contradiction`;
  /// a reaction entry already chosen as a reveal keeps `.revealed`. Output is
  /// capped at `limit` and finally sorted into transcript order.
  ///
  /// The tier-1 pass is kept **byte-identical to Stage 2** (transcript order,
  /// contradiction-wins de-dup, inline cap-break): a run with no reactions
  /// therefore produces exactly the Stage-2 result. This makes the "identical
  /// to today" guarantee structural, not test-dependent (#1109 critic).
  static func candidates(
    entries: [Entry],
    actualAgent: String?,
    limit: Int = defaultLimit
  ) -> [Selection] {
    // The reveal entry: the actual agent's last speak-phase output.
    let revealID: UUID? = actualAgent.flatMap { agent in
      entries.last { $0.agent == agent && isSpeakPhase($0.phaseType) }?.id
    }

    // Tier 1 — contradiction + reveal, verbatim from Stage 2.
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

    // Tier 2 — reaction fills only the remaining budget, in transcript order,
    // skipping entries already chosen by a stronger signal. Capping by the
    // *leftover* slots is what prevents the weakest positional signal from
    // evicting a verified contradiction / ground-truth reveal.
    if result.count < limit {
      let chosen = Set(result.map(\.id))
      for entry in entries where entry.isReaction && !chosen.contains(entry.id) {
        result.append(Selection(id: entry.id, reason: .reaction))
        if result.count >= limit { break }
      }
    }

    // Restore transcript order across both tiers so the section reads
    // chronologically regardless of which tier surfaced each pick.
    let position = Dictionary(
      entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    return result.sorted { (position[$0.id] ?? 0) < (position[$1.id] ?? 0) }
  }

  /// The ids of the entries that are "reactions" (💥, #1109) — the first
  /// speak-phase output after each event boundary, bounded to the same round.
  ///
  /// Walks `items` in transcript order: an `.eventBoundary` arms a pending
  /// reaction; the first following speak-phase `.output` consumes it (its id
  /// joins the set, one reaction per boundary); a `.roundBoundary` disarms
  /// without consuming (the event's same-round window closed). Non-speak
  /// outputs are skipped without disarming, so a skipped first speaker
  /// (ADR-021 — no `.output` emitted) naturally shifts the reaction to the
  /// next agent who actually speaks. Deterministic: same transcript ⇒ same ids.
  static func reactionEntryIDs(_ items: [ReactionItem]) -> Set<UUID> {
    var ids: Set<UUID> = []
    var armed = false
    for item in items {
      switch item {
      case .eventBoundary:
        armed = true
      case .roundBoundary:
        armed = false
      case .output(let id, let phaseType):
        if armed, isSpeakPhase(phaseType) {
          ids.insert(id)
          armed = false
        }
      }
    }
    return ids
  }

  /// The speak phases whose primary output is a public statement worth
  /// quoting on a card. Inlined here (not a `PhaseType` helper) to keep the
  /// change App-only — Models must not gain a member for this feature.
  private static func isSpeakPhase(_ phaseType: PhaseType) -> Bool {
    phaseType == .speakAll || phaseType == .speakEach
  }
}
