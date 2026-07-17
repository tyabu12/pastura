import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `ScenarioSerializerTests` (file_length cap). Per
// `.claude/rules/testing.md`, extend the suite struct rather than declaring a
// new `@Suite` (which would run in parallel and race shared state).
extension ScenarioSerializerTests {

  /// Round-trip guard for the `pairwise_payoff` `payoff:` table (ADR-027),
  /// including localized (CJK) `when` tokens — the motivating case the pre-ADR
  /// hardcoded English matrix could not express.
  @Test func roundTripPairwisePayoffTable() throws {
    let scenario = Scenario(
      id: "pairwise_roundtrip",
      name: "Pairwise",
      description: "A pairwise payoff scenario.",
      language: "ja",
      agentCount: 2,
      rounds: 1,
      context: "Context.",
      personas: [
        Persona(name: "Alice", description: "A"),
        Persona(name: "Bob", description: "B")
      ],
      phases: [
        Phase(
          type: .choose, options: ["協力", "裏切り"], pairing: .roundRobin),
        Phase(
          type: .scoreCalc, logic: .pairwisePayoff,
          payoff: [
            PayoffRule(when: ["協力", "協力"], points: [3, 3]),
            PayoffRule(when: ["協力", "裏切り"], points: [0, 5]),
            PayoffRule(when: ["裏切り", "協力"], points: [5, 0]),
            PayoffRule(when: ["裏切り", "裏切り"], points: [1, 1])
          ])
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    #expect(reloaded.phases[1].payoff == scenario.phases[1].payoff)
    #expect(reloaded.phases[1].logic == .pairwisePayoff)
  }

  /// An empty (non-nil) `payoff` table must not serialize to a childless
  /// `payoff:` line — that reloads as a null scalar `parsePayoff` rejects,
  /// breaking the round-trip. Both empty and nil are behavioural no-ops, so the
  /// serializer collapses empty→omitted (reloads as nil). Revert the
  /// `!payoff.isEmpty` gate and this test fails with a `.payoffNotList` throw.
  @Test func emptyPayoffTableOmittedNotEmittedAsNullKey() throws {
    let scenario = Scenario(
      id: "empty_payoff",
      name: "Empty",
      description: "d",
      language: "en",
      agentCount: 2,
      rounds: 1,
      context: "c",
      personas: [Persona(name: "Alice", description: "a"), Persona(name: "Bob", description: "b")],
      phases: [Phase(type: .scoreCalc, logic: .pairwisePayoff, payoff: [])]
    )

    let yaml = serializer.serialize(scenario)
    #expect(!yaml.contains("payoff:"))

    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.phases[0].payoff == nil)
  }
}
