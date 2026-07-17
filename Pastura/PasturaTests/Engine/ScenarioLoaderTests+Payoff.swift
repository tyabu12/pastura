import Testing

@testable import Pastura

/// Parse coverage for the `payoff:` table on a `pairwise_payoff` `score_calc`
/// phase (ADR-027). Guards the literal YAML key names + strict arity, which a
/// serializer↔loader round-trip alone cannot (a symmetric mis-key round-trips).
extension ScenarioLoaderTests {

  private var payoffHeader: String {
    """
    id: t
    language: ja
    name: T
    description: d
    agents: 2
    rounds: 1
    context: c
    personas:
      - name: Alice
        description: a
      - name: Bob
        description: b
    phases:
    """
  }

  @Test func parsesPayoffTableOnScoreCalc() throws {
    let yaml =
      payoffHeader + """

          - type: choose
            options: [協力, 裏切り]
            pairing: round_robin
          - type: score_calc
            logic: pairwise_payoff
            payoff:
              - when: [協力, 協力]
                points: [3, 3]
              - when: [裏切り, 裏切り]
                points: [1, 1]
        """
    let scenario = try loader.load(yaml: yaml)
    let payoff = try #require(scenario.phases[1].payoff)
    #expect(payoff.count == 2)
    #expect(payoff[0] == PayoffRule(when: ["協力", "協力"], points: [3, 3]))
    #expect(payoff[1] == PayoffRule(when: ["裏切り", "裏切り"], points: [1, 1]))
  }

  @Test func absentPayoffLeavesNilNotThrow() throws {
    // `load` stays non-validating (#665): a pairwise_payoff phase with no
    // `payoff:` loads with `payoff == nil` — the guaranteed-no-op is a linter
    // concern (R20a), not a load throw.
    let yaml =
      payoffHeader + """

          - type: score_calc
            logic: pairwise_payoff
        """
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.phases[0].payoff == nil)
  }

  @Test func throwsOnWhenArityNotTwo() throws {
    let yaml =
      payoffHeader + """

          - type: score_calc
            logic: pairwise_payoff
            payoff:
              - when: [協力]
                points: [3, 3]
        """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    // The message template names both fields, so assert the discriminating
    // detail suffix, not a bare "when" substring.
    #expect(msg.contains("'when' must be 2 strings"))
  }

  @Test func throwsOnPointsArityNotTwo() throws {
    let yaml =
      payoffHeader + """

          - type: score_calc
            logic: pairwise_payoff
            payoff:
              - when: [協力, 協力]
                points: [3]
        """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'points' must be 2 ints"))
  }

  @Test func throwsOnPayoffNotList() throws {
    let yaml =
      payoffHeader + """

          - type: score_calc
            logic: pairwise_payoff
            payoff: not_a_list
        """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("payoff"))
  }
}
