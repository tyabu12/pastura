import Foundation
import Testing

@testable import Pastura

/// Parse + serialize coverage for scenarios containing `conditional` phases.
/// Complements the preset-round-trip tests in `ScenarioSerializerTests` by
/// exercising the conditional-specific YAML shape (`if:` / `then:` / `else:`)
/// and the loader-level depth-1 rejection.
@Suite(.timeLimit(.minutes(1)))
// swiftlint:disable:next type_body_length
struct ConditionalScenarioIOTests {
  let loader = ScenarioLoader()
  let serializer = ScenarioSerializer()

  // MARK: - Parse

  @Test func loadsConditionalWithBothBranches() throws {
    let yaml = """
      id: test
      name: Test
      description: test
      agents: 2
      rounds: 1
      context: ctx
      personas:
        - name: Alice
          description: a
        - name: Bob
          description: b
      phases:
        - type: conditional
          if: "max_score >= 10"
          then:
            - type: summarize
              template: won
          else:
            - type: speak_all
              prompt: keep going
              output:
                statement: string
      """

    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.phases.count == 1)

    let phase = scenario.phases[0]
    #expect(phase.type == .conditional)
    #expect(phase.condition == "max_score >= 10")
    #expect(phase.thenPhases?.count == 1)
    #expect(phase.thenPhases?.first?.type == .summarize)
    #expect(phase.thenPhases?.first?.template == "won")
    #expect(phase.elsePhases?.count == 1)
    #expect(phase.elsePhases?.first?.type == .speakAll)
    #expect(phase.elsePhases?.first?.prompt == "keep going")
  }

  @Test func loadsConditionalWithOnlyThenBranch() throws {
    let yaml = """
      id: test
      name: Test
      description: test
      agents: 2
      rounds: 1
      context: ctx
      personas:
        - name: Alice
          description: a
        - name: Bob
          description: b
      phases:
        - type: conditional
          if: "current_round == 1"
          then:
            - type: summarize
              template: intro
      """

    let scenario = try loader.load(yaml: yaml)
    let phase = scenario.phases[0]
    #expect(phase.thenPhases?.count == 1)
    // Unspecified `else:` parses as nil — the handler falls back to a no-op
    // branch when the condition is false.
    #expect(phase.elsePhases == nil)
  }

  // MARK: - Depth-1 enforcement at load time

  @Test func rejectsNestedConditionalInThenBranch() throws {
    let yaml = """
      id: test
      name: Test
      description: test
      agents: 2
      rounds: 1
      context: ctx
      personas:
        - name: Alice
          description: a
        - name: Bob
          description: b
      phases:
        - type: conditional
          if: "current_round == 1"
          then:
            - type: conditional
              if: "max_score > 0"
              then:
                - type: summarize
                  template: nested
      """

    #expect(throws: SimulationError.self) {
      _ = try loader.load(yaml: yaml)
    }
  }

  @Test func rejectsNestedConditionalInElseBranch() throws {
    let yaml = """
      id: test
      name: Test
      description: test
      agents: 2
      rounds: 1
      context: ctx
      personas:
        - name: Alice
          description: a
        - name: Bob
          description: b
      phases:
        - type: conditional
          if: "current_round == 1"
          then:
            - type: summarize
              template: fine
          else:
            - type: conditional
              if: "current_round == 2"
              then:
                - type: summarize
                  template: bad
      """

    #expect(throws: SimulationError.self) {
      _ = try loader.load(yaml: yaml)
    }
  }

  // MARK: - Round-trip

  @Test func roundTripConditionalPreservesFields() throws {
    let scenario = Scenario(
      id: "rt",
      name: "RT",
      description: "round trip",
      agentCount: 2,
      rounds: 1,
      context: "ctx",
      personas: [
        Persona(name: "Alice", description: "a"),
        Persona(name: "Bob", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "max_score >= 10",
          thenPhases: [
            Phase(type: .summarize, template: "won")
          ],
          elsePhases: [
            Phase(
              type: .speakAll,
              prompt: "keep going",
              outputSchema: ["statement": "string"]
            )
          ]
        )
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    #expect(reloaded.phases.count == 1)
    let phase = reloaded.phases[0]
    #expect(phase.type == .conditional)
    #expect(phase.condition == "max_score >= 10")
    #expect(phase.thenPhases?.count == 1)
    #expect(phase.thenPhases?.first?.type == .summarize)
    #expect(phase.thenPhases?.first?.template == "won")
    #expect(phase.elsePhases?.count == 1)
    #expect(phase.elsePhases?.first?.type == .speakAll)
    #expect(phase.elsePhases?.first?.prompt == "keep going")
  }

  @Test func roundTripConditionWithOperatorCharsIsQuoted() throws {
    let scenario = Scenario(
      id: "rt2",
      name: "RT",
      description: "round trip with special chars",
      agentCount: 2,
      rounds: 1,
      context: "ctx",
      personas: [
        Persona(name: "Alice", description: "a"),
        Persona(name: "Bob", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "vote_winner == \"Alice\"",
          thenPhases: [Phase(type: .summarize, template: "picked")]
        )
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    let cond = reloaded.phases[0].condition
    // Serialize-then-parse must preserve the embedded double quotes so the
    // ConditionEvaluator still reads a string literal on the RHS.
    #expect(cond == "vote_winner == \"Alice\"")
  }

  @Test func roundTripEmptyElseBranchPreservesEmpty() throws {
    let scenario = Scenario(
      id: "rt3",
      name: "RT",
      description: "empty else",
      agentCount: 2,
      rounds: 1,
      context: "ctx",
      personas: [
        Persona(name: "Alice", description: "a"),
        Persona(name: "Bob", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [Phase(type: .summarize, template: "t")],
          elsePhases: []
        )
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)
    // An emitted `else:` with no items parses as `nil` (YAML sequence of zero
    // items is indistinguishable from "absent"). The handler's empty-branch
    // no-op behavior covers both cases identically, so this lossy round-trip
    // is acceptable and the handler test asserts the run-time equivalence.
    let phase = reloaded.phases[0]
    #expect(phase.thenPhases?.count == 1)
    #expect(phase.elsePhases == nil || phase.elsePhases?.isEmpty == true)
  }

  // MARK: - Inference estimation with conditional

  @Test func estimateInferenceCountUsesMaxOfBranches() throws {
    let scenario = Scenario(
      id: "est",
      name: "est",
      description: "estimator",
      agentCount: 2,
      rounds: 3,
      context: "ctx",
      personas: [
        Persona(name: "Alice", description: "a"),
        Persona(name: "Bob", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            // speak_all (2 agents) = 2 inferences per round
            Phase(type: .speakAll, prompt: "p", outputSchema: ["statement": "string"])
          ],
          elsePhases: [
            // vote (2 agents) = 2 inferences per round
            Phase(type: .vote, prompt: "v", outputSchema: ["vote": "string"])
          ]
        )
      ]
    )

    // max(2, 2) × 3 rounds = 6 (not 4 × 3 = 12 that `sum` would give).
    let estimate = ScenarioLoader.estimateInferenceCount(scenario)
    #expect(estimate == 6)
  }

  @Test func estimateInferenceCountAsymmetricBranchesTakesMax() throws {
    let scenario = Scenario(
      id: "asym",
      name: "asym",
      description: "asymmetric",
      agentCount: 2,
      rounds: 2,
      context: "ctx",
      personas: [
        Persona(name: "Alice", description: "a"),
        Persona(name: "Bob", description: "b")
      ],
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 99",  // rare
          thenPhases: [
            Phase(
              type: .speakEach, prompt: "p", outputSchema: ["statement": "string"],
              subRounds: 3)
          ],
          elsePhases: [
            Phase(type: .summarize, template: "s")  // 0 inferences
          ]
        )
      ]
    )

    // max(6, 0) × 2 = 12.
    let estimate = ScenarioLoader.estimateInferenceCount(scenario)
    #expect(estimate == 12)
  }
}
