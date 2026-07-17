import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `ScenarioYAMLPatcherTests` (file_length cap). Per
// `.claude/rules/testing.md`, extend the suite struct rather than declaring a
// new `@Suite`.
extension ScenarioYAMLPatcherTests {

  /// ADR-018 × ADR-027: `payoff` is a nested list with no visual editor field,
  /// so a scalar visual edit must leave the `payoff:` block byte-intact. Guards
  /// against the surgical patcher silently dropping the nested table.
  private var payoffBase: String {
    """
    id: pairwise_demo
    language: ja
    name: Original Name  # display name
    description: A pairwise scenario
    agents: 2
    rounds: 3
    context: Shared context.
    personas:
      - name: Alice
        description: An optimistic agent
      - name: Bob
        description: A skeptical agent
    phases:
      - type: choose
        options: [協力, 裏切り]
        pairing: round_robin
        output:
          action: string
      - type: score_calc
        logic: pairwise_payoff
        payoff:
          - when: [協力, 協力]
            points: [3, 3]
          - when: [裏切り, 裏切り]
            points: [1, 1]
    """
  }

  @Test func scalarEditPreservesPayoffBlock() throws {
    let baseScenario = try loader.load(yaml: payoffBase)
    let visual = mutated(baseScenario, name: "New Name")
    let out = patcher.patch(visual: visual, base: payoffBase)

    // The edited scalar changed…
    #expect(out.contains("name: New Name  # display name"))
    // …while the untouched nested payoff block survives verbatim.
    #expect(out.contains("logic: pairwise_payoff"))
    #expect(out.contains("- when: [協力, 協力]"))
    #expect(out.contains("points: [3, 3]"))
    #expect(out.contains("- when: [裏切り, 裏切り]"))
    // And the patched output re-parses to the same scenario.
    #expect(try loader.load(yaml: out) == visual)
  }
}
