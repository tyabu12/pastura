// Producer–consumer ordering rules R1–R6 (ADR-022 D3). Extension of the
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
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .choose), Phase(type: .scoreCalc, logic: .prisonersDilemma)])
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
        Phase(type: .choose, pairing: .roundRobin),
        Phase(type: .scoreCalc, logic: .prisonersDilemma)
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func roundRobinChooseInsideConditionalSatisfiesPrisonersDilemma() {
    let conditional = Phase(
      type: .conditional, condition: "current_round >= 1",
      thenPhases: [Phase(type: .choose, pairing: .roundRobin)])
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [conditional, Phase(type: .scoreCalc, logic: .prisonersDilemma)])
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
