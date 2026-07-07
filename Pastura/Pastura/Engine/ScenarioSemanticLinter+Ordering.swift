import Foundation

/// Producer–consumer phase-ordering rules R1–R6 (ADR-022 D3).
///
/// Each rule compares **phase-list indices**: a consuming phase
/// (`eliminate` / `score_calc`) needs its producer (`vote`, round-robin
/// `choose`, `assign random_one`, dict-shaped `event_inject`) to run earlier
/// in the round, or it silently no-ops / scores on a stale value.
///
/// Two shared semantics (both deliberate imprecisions recorded in the ADR):
///
/// - **Producer inside a `conditional` branch counts as present at the
///   conditional's top-level index** (may-run suffices — it avoids
///   false-positive errors at the cost of missing branch-only producers).
/// - **A consumer inside a `conditional` branch anchors its finding to the
///   conditional's top-level index** (`eliminate` / `score_calc` are allowed
///   inside branches). "Earlier" is therefore `index <= consumerIndex`, so a
///   producer sharing the consumer's enclosing conditional is treated as
///   satisfying the dependency rather than flagged.
nonisolated extension ScenarioSemanticLinter {

  /// A phase paired with the top-level phase-list index its finding anchors
  /// to (the enclosing conditional's index when nested in a branch).
  ///
  /// `internal` (not `private`) — reused by `ScenarioSemanticLinter+Config.swift`
  /// (R7/R8/R9/R17), which shares this file's traversal semantics rather than
  /// duplicating them.
  struct PhaseRef {
    let phase: Phase
    let topLevelIndex: Int
  }

  /// Producer–consumer ordering findings (R1a/R1b/R2/R3/R5/R6).
  func orderingFindings(in scenario: Scenario) -> [LintFinding] {
    let phases = scenario.phases
    let votes = producerIndices(in: phases) { $0.type == .vote }
    let roundRobinChoose = producerIndices(in: phases) {
      $0.type == .choose && $0.pairing == .roundRobin
    }
    let assignRandomOne = producerIndices(in: phases) {
      $0.type == .assign && ($0.target ?? .all) == .randomOne
    }
    let eventInject = producerIndices(in: phases) {
      isQualifyingEventInject($0, scenario: scenario)
    }

    var findings: [LintFinding] = []
    for consumer in phaseRefs(in: phases, where: isOrderingConsumer) {
      switch consumer.phase.type {
      case .eliminate:
        findings += eliminateFindings(consumer, votes: votes)
      case .scoreCalc:
        findings += scoreCalcFindings(
          consumer, votes: votes, roundRobinChoose: roundRobinChoose,
          assignRandomOne: assignRandomOne, eventInject: eventInject)
      default:
        break
      }
    }
    findings += relationshipPlacementFindings(in: scenario)
    return findings
  }

  // MARK: - R4 relationship-update-placement (warning)

  /// R4 `relationship-update-placement` — a top-level `relationship_update`
  /// whose declared update rules can't see the signals they read.
  ///
  /// `relationship_update` is **top-level only** (the validator bans it inside
  /// conditional branches), so this scans top-level phases. Producers, however,
  /// may sit inside a `conditional` branch and still count (may-run, `< i` via
  /// ``producerIndices(in:where:)``).
  ///
  /// Predicates derive from `RelationshipUpdateHandler`'s actual reads — each
  /// declared rule reads a different piece of state, and each is lost by a
  /// distinct placement mistake:
  ///
  /// - **`voteAgainst`** reads `state.lastOutputs[voter].vote`. Broken when
  ///   (a) no `vote` runs before this phase, or (b) a `lastOutputs`-writing LLM
  ///   phase overwrites the voter's entry between the last preceding `vote` and
  ///   this phase. `speak_all` / `speak_each` / `choose` all write `lastOutputs`
  ///   (verified in their handlers) and carry no `vote` field, so they drop the
  ///   signal; a *second* `vote` merely rewrites a fresher vote (not a loss) and
  ///   is excluded; `reflect` / `whisper` never touch `lastOutputs` and are safe
  ///   interleaves.
  /// - **`actionDeltas`** reads `state.pairings`, populated only by a
  ///   round-robin `choose`. Broken when (a) no round-robin `choose` runs before
  ///   this phase, or (b) a `prisoners_dilemma` `score_calc` clears
  ///   `state.pairings` (see `PrisonersDilemmaLogic`) between the LAST preceding
  ///   round-robin `choose` and this phase — a later choose surviving un-cleared
  ///   satisfies the rule (no false positive).
  ///
  /// One finding per phase max. Fires when ANY declared rule's signal is lost:
  /// a phase declaring both rules where only one is reachable is still a real
  /// (partial) placement bug the author should see. A phase declaring neither
  /// rule can't reach here — `ScenarioValidator.validateRelationshipUpdateShape`
  /// rejects it upstream.
  private func relationshipPlacementFindings(in scenario: Scenario) -> [LintFinding] {
    let phases = scenario.phases
    let votes = producerIndices(in: phases) { $0.type == .vote }
    let roundRobinChoose = producerIndices(in: phases) {
      $0.type == .choose && $0.pairing == .roundRobin
    }
    let pdScoreCalc = producerIndices(in: phases) {
      $0.type == .scoreCalc && $0.logic == .prisonersDilemma
    }
    // `lastOutputs`-writers that DROP the vote field. A second `vote` rewrites a
    // fresher vote rather than losing it, so `.vote` is excluded here.
    let voteSignalLosers = producerIndices(in: phases) {
      $0.type == .speakAll || $0.type == .speakEach || $0.type == .choose
    }

    var findings: [LintFinding] = []
    // Top-level scan: `relationship_update` is never nested in a branch.
    for (i, phase) in phases.enumerated() where phase.type == .relationshipUpdate {
      let voteBroken =
        phase.voteAgainst != nil
        && voteSignalUnreachable(before: i, votes: votes, losers: voteSignalLosers)
      let actionBroken =
        !(phase.actionDeltas ?? [:]).isEmpty
        && actionSignalUnreachable(before: i, choose: roundRobinChoose, clears: pdScoreCalc)
      if voteBroken || actionBroken {
        findings += finding("relationship-update-placement", .warning, at: i)
      }
    }
    return findings
  }

  /// Whether a `vote_against` rule at top-level index `i` can't read a vote:
  /// no `vote` precedes it, or a `lastOutputs`-overwriting phase sits between
  /// the last preceding `vote` and it.
  private func voteSignalUnreachable(before i: Int, votes: Set<Int>, losers: Set<Int>) -> Bool {
    guard let lastVote = votes.filter({ $0 < i }).max() else { return true }
    return losers.contains { $0 > lastVote && $0 < i }
  }

  /// Whether an `action_deltas` rule at top-level index `i` can't read pairings:
  /// no round-robin `choose` precedes it, or a pairings-clearing
  /// `prisoners_dilemma` `score_calc` sits between the last preceding
  /// round-robin `choose` and it (a later un-cleared choose satisfies the rule).
  private func actionSignalUnreachable(before i: Int, choose: Set<Int>, clears: Set<Int>) -> Bool {
    guard let lastChoose = choose.filter({ $0 < i }).max() else { return true }
    return clears.contains { $0 > lastChoose && $0 < i }
  }

  // MARK: - Per-consumer rules

  /// R1a `eliminate-needs-vote` (error) + R1b `eliminate-after-vote` (warning).
  private func eliminateFindings(_ consumer: PhaseRef, votes: Set<Int>) -> [LintFinding] {
    let idx = consumer.topLevelIndex
    if votes.isEmpty {
      return finding("eliminate-needs-vote", .error, at: idx)
    }
    if !votes.contains(where: { $0 <= idx }) {
      return finding("eliminate-after-vote", .warning, at: idx)
    }
    return []
  }

  /// R2/R3/R5/R6 — the `score_calc` logic-specific producer dependencies.
  private func scoreCalcFindings(
    _ consumer: PhaseRef, votes: Set<Int>, roundRobinChoose: Set<Int>,
    assignRandomOne: Set<Int>, eventInject: Set<Int>
  ) -> [LintFinding] {
    let idx = consumer.topLevelIndex
    switch consumer.phase.logic {
    case .prisonersDilemma:
      guard !roundRobinChoose.contains(where: { $0 <= idx }) else { return [] }
      return finding("pd-needs-round-robin-choose", .error, at: idx)
    case .wordwolfJudge:
      let hasAssign = assignRandomOne.contains { $0 <= idx }
      let hasVote = votes.contains { $0 <= idx }
      guard !(hasAssign && hasVote) else { return [] }
      return finding("wordwolf-needs-assign-and-vote", .error, at: idx)
    case .eventReactive:
      guard !eventInject.contains(where: { $0 <= idx }) else { return [] }
      return finding("event-reactive-needs-event-inject", .error, at: idx)
    case .voteTally:
      guard !votes.contains(where: { $0 <= idx }) else { return [] }
      return finding("vote-tally-needs-vote", .warning, at: idx)
    case .none:
      // Missing `logic` is a `ScenarioValidator` / handler error, not a lint
      // concern — the linter doesn't second-guess it here.
      return []
    }
  }

  /// Builds the single-element findings array for an ordering `ruleID`,
  /// resolving its fix-hint message via ``orderingMessage(_:)``.
  private func finding(
    _ ruleID: String, _ severity: LintSeverity, at idx: Int
  ) -> [LintFinding] {
    [
      LintFinding(
        ruleID: ruleID, severity: severity, message: orderingMessage(ruleID), phaseIndex: idx)
    ]
  }

  /// The user-facing fix-hint message for an ordering `ruleID` (one sentence
  /// naming the rule + a concrete fix).
  private func orderingMessage(_ ruleID: String) -> String {
    switch ruleID {
    case "eliminate-needs-vote":
      return String(
        localized:
          "eliminate-needs-vote: an 'eliminate' phase does nothing without a 'vote' phase in the same round — add a 'vote' phase before it."
      )
    case "eliminate-after-vote":
      return String(
        localized:
          "eliminate-after-vote: this 'eliminate' runs before every 'vote' phase, so it acts on the previous round's stale tally — move it after the 'vote' phase."
      )
    case "pd-needs-round-robin-choose":
      return String(
        localized:
          "pd-needs-round-robin-choose: 'prisoners_dilemma' scoring needs a round-robin 'choose' phase earlier in the round to populate pairings, or scores never change — add one before this 'score_calc'."
      )
    case "wordwolf-needs-assign-and-vote":
      return String(
        localized:
          "wordwolf-needs-assign-and-vote: 'wordwolf_judge' scoring needs both an 'assign' phase with target 'random_one' and a 'vote' phase earlier in the round, or it judges nothing — add the missing phase(s) before this 'score_calc'."
      )
    case "event-reactive-needs-event-inject":
      return String(
        localized:
          "event-reactive-needs-event-inject: 'event_reactive' scoring needs an earlier 'event_inject' phase with a dictionary event source and the default 'as: current_event', or the favored action is never scored — fix the 'event_inject' before this 'score_calc'."
      )
    case "relationship-update-placement":
      return String(
        localized:
          "relationship-update-placement: this 'relationship_update' cannot see its vote/choose signals — place it after the producing 'vote'/'choose' phase and before any 'prisoners_dilemma' 'score_calc', with no 'speak'/'choose' phase between the vote and it."
      )
    default:
      return String(
        localized:
          "vote-tally-needs-vote: 'vote_tally' scoring has no 'vote' phase earlier in the round, so it scores nothing or re-adds a stale tally — add a 'vote' phase before this 'score_calc'."
      )
    }
  }

  // MARK: - Traversal helpers

  /// Top-level indices at which `predicate` matches — the phase itself, or any
  /// of its `conditional` sub-phases (may-run counts as present).
  ///
  /// `internal` — shared with `ScenarioSemanticLinter+Config.swift` (R9's
  /// round-robin-`choose` producer lookup).
  func producerIndices(
    in phases: [Phase], where predicate: (Phase) -> Bool
  ) -> Set<Int> {
    var result: Set<Int> = []
    for (index, phase) in phases.enumerated()
    where predicate(phase) || branchPhases(of: phase).contains(where: predicate) {
      result.insert(index)
    }
    return result
  }

  /// Every phase matching `predicate`, top-level or nested in a `conditional`
  /// branch, anchored to its top-level index.
  ///
  /// `internal` — shared with `ScenarioSemanticLinter+Config.swift` (R7/R8/R9's
  /// per-phase-type scans and R17's `speak_each` presence check).
  func phaseRefs(in phases: [Phase], where predicate: (Phase) -> Bool) -> [PhaseRef] {
    var result: [PhaseRef] = []
    for (index, phase) in phases.enumerated() {
      if predicate(phase) {
        result.append(PhaseRef(phase: phase, topLevelIndex: index))
      }
      for sub in branchPhases(of: phase) where predicate(sub) {
        result.append(PhaseRef(phase: sub, topLevelIndex: index))
      }
    }
    return result
  }

  private func isOrderingConsumer(_ phase: Phase) -> Bool {
    phase.type == .eliminate || phase.type == .scoreCalc
  }

  /// The `then` + `else` sub-phases of a `conditional` (empty for other types).
  /// Depth-1 is enforced upstream, so no recursion is needed.
  ///
  /// `internal` — shared with `ScenarioSemanticLinter+Config.swift` (R17's
  /// nested-`speak_each` check).
  func branchPhases(of phase: Phase) -> [Phase] {
    (phase.thenPhases ?? []) + (phase.elsePhases ?? [])
  }

  /// Whether an `event_inject` phase writes the `current_event__favors`
  /// companion variable `EventReactivePayoffLogic` reads: dict-shaped source
  /// (`{text, favors}` → `.arrayOfDictionaries`) AND the default `as:` name
  /// (`ScoreCalcHandler` hardcodes `favoredVariableName(for: defaultVariableName)`).
  private func isQualifyingEventInject(_ phase: Phase, scenario: Scenario) -> Bool {
    guard phase.type == .eventInject, phase.eventVariable == nil,
      let key = phase.source,
      case .arrayOfDictionaries = scenario.extraData[key]
    else { return false }
    return true
  }
}
