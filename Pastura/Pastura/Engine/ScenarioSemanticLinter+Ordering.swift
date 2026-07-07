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
    return findings
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
  /// naming the rule + a concrete fix). Catalog `ja` fill is a later item.
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
