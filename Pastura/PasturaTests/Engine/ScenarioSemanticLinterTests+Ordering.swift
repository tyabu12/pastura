// Producer–consumer ordering rules R1–R6 (ADR-024 D3). Extension of the
// existing suite (not a new @Suite) per .claude/rules/testing.md splitting
// pattern — reuses `linter` / `makeScenario` from the base file.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  // MARK: - R1a eliminate-needs-vote (error)

  @Test func eliminateWithoutAnyVoteFiresError() {
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [Phase(type: .eliminate)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "eliminate-needs-vote")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func eliminateAfterVotePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .vote), Phase(type: .eliminate)])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func voteInsideConditionalBranchSatisfiesEliminate() {
    // May-run: a vote nested in a conditional branch counts as present at the
    // conditional's index, so a following eliminate does not fire R1a.
    let conditional = Phase(
      type: .conditional, condition: "current_round >= 1", thenPhases: [Phase(type: .vote)])
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditional, Phase(type: .eliminate)])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func sameConditionalVoteBeforeEliminatePassesOrdering() {
    // Regression for the ordering rules' `<=` may-run leniency: a vote and its
    // eliminate consumer ordered inside ONE conditional branch both anchor to
    // the conditional's top-level index. Reverting `<=` to `<` in
    // eliminateFindings would false-fire R1b here.
    let conditional = Phase(
      type: .conditional, condition: "current_round >= 1",
      thenPhases: [Phase(type: .vote), Phase(type: .eliminate)])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [conditional])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R1b eliminate-after-vote (warning)

  @Test func eliminateBeforeVoteFiresWarning() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .eliminate), Phase(type: .vote)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "eliminate-after-vote")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func eliminateCorrectlyOrderedAfterVoteHasNoWarning() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .vote), Phase(type: .eliminate)])
    #expect(linter.lint(scenario).allSatisfy { $0.ruleID != "eliminate-after-vote" })
  }

  // MARK: - R2 pd-needs-round-robin-choose (error)

  @Test func prisonersDilemmaWithoutRoundRobinChooseFiresError() {
    // An individual (non-round-robin) choose does NOT populate pairings.
    // `options` set so this fixture doesn't also trip R7
    // (choose-should-declare-options, ADR-024 D3, orthogonal to ordering).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"]),
        Phase(type: .scoreCalc, logic: .prisonersDilemma)
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "pd-needs-round-robin-choose")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 1)
  }

  @Test func prisonersDilemmaWithRoundRobinChoosePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .prisonersDilemma)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func roundRobinChooseInsideConditionalSatisfiesPrisonersDilemma() {
    let conditional = Phase(
      type: .conditional, condition: "current_round >= 1",
      thenPhases: [Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin)])
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [conditional, Phase(type: .scoreCalc, logic: .prisonersDilemma)])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R19 pairwise-payoff-needs-round-robin-choose (error)

  /// A four-row payoff table over `{cooperate, betray}²` — satisfiable by the
  /// `["cooperate", "betray"]` option set, so R20a (item 3) stays silent and
  /// these fixtures isolate R19.
  private var pdPayoff: [PayoffRule] {
    [
      PayoffRule(when: ["cooperate", "cooperate"], points: [3, 3]),
      PayoffRule(when: ["cooperate", "betray"], points: [0, 5]),
      PayoffRule(when: ["betray", "cooperate"], points: [5, 0]),
      PayoffRule(when: ["betray", "betray"], points: [1, 1])
    ]
  }

  @Test func pairwisePayoffWithoutRoundRobinChooseFiresError() {
    // R19 mirrors R2 but keeps a distinct ruleID: an individual (non-round-robin)
    // choose does not populate pairings, so a pairwise_payoff score_calc scores
    // nothing. A `pd-`-named finding here would name the wrong mechanic.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"]),
        Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: pdPayoff)
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "pairwise-payoff-needs-round-robin-choose")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 1)
  }

  @Test func pairwisePayoffWithRoundRobinChoosePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: pdPayoff)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R3 wordwolf-needs-assign-and-vote (error)

  @Test func wordwolfWithoutAssignAndVoteFiresError() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .scoreCalc, logic: .wordwolfJudge)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "wordwolf-needs-assign-and-vote")
    #expect(findings.first?.severity == .error)
  }

  @Test func wordwolfWithOnlyVoteStillFiresError() {
    // Missing the assign random_one producer of wolf_name → still an error.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .vote), Phase(type: .scoreCalc, logic: .wordwolfJudge)])
    #expect(linter.lint(scenario).contains { $0.ruleID == "wordwolf-needs-assign-and-vote" })
  }

  @Test func wordwolfWithAssignRandomOneAndVotePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .assign, target: .randomOne),
        Phase(type: .vote),
        Phase(type: .scoreCalc, logic: .wordwolfJudge)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R5 event-reactive-needs-event-inject (error)

  @Test func eventReactiveWithCustomAsFiresError() {
    // A custom `as:` writes `<custom>__favors`, but ScoreCalcHandler reads the
    // hardcoded `current_event__favors` → favored action never scored.
    let scenario = makeEventScenario(
      phases: [
        Phase(type: .eventInject, source: "events", eventVariable: "my_event"),
        Phase(type: .scoreCalc, logic: .eventReactive)
      ],
      events: .arrayOfDictionaries([["text": "storm", "favors": "cooperate"]]))
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "event-reactive-needs-event-inject")
    #expect(findings.first?.severity == .error)
  }

  @Test func eventReactiveWithStringListSourceFiresError() {
    // A plain [String] source never writes the companion favored variable.
    let scenario = makeEventScenario(
      phases: [
        Phase(type: .eventInject, source: "events"),
        Phase(type: .scoreCalc, logic: .eventReactive)
      ],
      events: .array(["storm", "calm"]))
    #expect(linter.lint(scenario).contains { $0.ruleID == "event-reactive-needs-event-inject" })
  }

  @Test func eventReactiveWithDictSourceAndDefaultAsPasses() {
    let scenario = makeEventScenario(
      phases: [
        Phase(type: .eventInject, source: "events"),
        Phase(type: .scoreCalc, logic: .eventReactive)
      ],
      events: .arrayOfDictionaries([["text": "storm", "favors": "cooperate"]]))
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R6 vote-tally-needs-vote (warning)

  @Test func voteTallyWithoutVoteFiresWarning() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .scoreCalc, logic: .voteTally)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "vote-tally-needs-vote")
    #expect(findings.first?.severity == .warning)
  }

  @Test func voteTallyWithVotePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .vote), Phase(type: .scoreCalc, logic: .voteTally)])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R4 relationship-update-placement (warning)

  @Test func relationshipUpdateVoteAgainstWithoutVoteFiresWarning() {
    // voteAgainst declared but no `vote` earlier → the vote signal is never
    // produced, so the delta silently does nothing.
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .relationshipUpdate, voteAgainst: -1)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "relationship-update-placement")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func relationshipUpdateActionDeltasWithoutRoundRobinChooseFiresWarning() {
    // An individual (non-round-robin) choose does NOT populate pairings, so
    // action_deltas has nothing to read.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"]),
        Phase(type: .relationshipUpdate, actionDeltas: ["cooperate": 1])
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "relationship-update-placement")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 1)
  }

  @Test func relationshipUpdateWithPrisonersDilemmaBetweenChooseAndItFiresWarning() {
    // PD score_calc clears pairings between the choose and the relationship_update
    // → action_deltas reads empty pairings.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .prisonersDilemma),
        Phase(type: .relationshipUpdate, actionDeltas: ["cooperate": 1, "betray": -1])
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "relationship-update-placement")
    #expect(findings.first?.phaseIndex == 2)
  }

  @Test func relationshipUpdateWithPairwisePayoffBetweenChooseAndItFiresWarning() {
    // R4 regression (ADR-027): pairwise_payoff clears state.pairings exactly like
    // prisoners_dilemma, so it must join the pairings-clearing producer set. If
    // the `==` predicate omits it, R4 silently stops firing here (false negative).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: pdPayoff),
        Phase(type: .relationshipUpdate, actionDeltas: ["cooperate": 1, "betray": -1])
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "relationship-update-placement")
    #expect(findings.first?.phaseIndex == 2)
  }

  @Test func relationshipUpdateWithChooseAfterPrisonersDilemmaPasses() {
    // A fresh round-robin choose after the clearing PD repopulates pairings, so
    // the un-cleared choose satisfies the action rule.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .prisonersDilemma),
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .relationshipUpdate, actionDeltas: ["cooperate": 1])
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func relationshipUpdateWithSpeakAllBetweenVoteAndItFiresWarning() {
    // speak_all overwrites lastOutputs between the vote and the phase, dropping
    // the `.vote` field the voteAgainst rule reads.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .vote),
        Phase(type: .speakAll),
        Phase(type: .relationshipUpdate, voteAgainst: -1)
      ])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "relationship-update-placement")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 2)
  }

  @Test func relationshipUpdateWithReflectBetweenVoteAndItPasses() {
    // reflect does NOT write lastOutputs, so the vote signal survives.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .vote),
        Phase(type: .reflect),
        Phase(type: .relationshipUpdate, voteAgainst: -1)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func relationshipUpdateCorrectlyPlacedPasses() {
    // round-robin choose → vote → relationship_update (both rules) → PD score_calc:
    // both signals are readable, and the pairings-clearing PD runs after the phase.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .vote),
        Phase(
          type: .relationshipUpdate, voteAgainst: -1,
          actionDeltas: ["cooperate": 1, "betray": -1]),
        Phase(type: .scoreCalc, logic: .prisonersDilemma)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - Helper

  // Internal factory for scenarios needing `extraData` (R5); the base
  // `makeScenario` doesn't take extraData.
  func makeEventScenario(phases: [Phase], events: AnyCodableValue) -> Scenario {
    Scenario(
      id: "test", name: "Test", description: "Test",
      language: "ja",
      agentCount: 2, rounds: 1, context: "Context",
      personas: [Persona(name: "A0", description: "D"), Persona(name: "A1", description: "D")],
      phases: phases,
      extraData: ["events": events]
    )
  }
}
