import Foundation
import Testing

@testable import Pastura

/// Regression for the multi-line block-scalar re-indent bug: if a conditional
/// sub-phase has a multi-line `template:` or `prompt:` value, the serializer
/// must preserve the block-scalar indentation so the round-tripped YAML
/// still parses. See code-reviewer finding dated 2026-04-19.
@Suite(.timeLimit(.minutes(1)))
struct ConditionalMultiLineSerializerTest {
  let loader = ScenarioLoader()
  let serializer = ScenarioSerializer()

  @Test func multiLineTemplateInThenBranchRoundTrips() throws {
    let scenario = Scenario(
      id: "mlrt",
      name: "Multi-line",
      description: "Tests multi-line template inside a then-branch",
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
          condition: "max_score >= 3",
          thenPhases: [
            Phase(
              type: .summarize,
              template: "line one\nline two\nline three"
            )
          ]
        )
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    #expect(reloaded.phases.count == 1)
    let phase = reloaded.phases[0]
    #expect(phase.thenPhases?.count == 1)
    let template = phase.thenPhases?.first?.template ?? "<nil>"
    // Yams' literal block scalar `|` appends a trailing newline per YAML
    // spec (clip chomping). Accept either the stripped or the with-newline
    // form — the important invariant is that the interior newlines are
    // preserved, which is what the multi-line scalar corruption bug broke.
    #expect(
      template == "line one\nline two\nline three"
        || template == "line one\nline two\nline three\n",
      "template: \(template.debugDescription), yaml:\n\(yaml)"
    )
  }

  @Test func multiLinePromptInElseBranchRoundTrips() throws {
    let scenario = Scenario(
      id: "mlrt2",
      name: "Multi-line prompt",
      description: "Tests multi-line prompt inside an else-branch",
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
          condition: "current_round == 99",
          thenPhases: [Phase(type: .summarize, template: "won")],
          elsePhases: [
            Phase(
              type: .speakAll,
              prompt: "Current scores: {scoreboard}\nWhat is your strategy?",
              outputSchema: ["statement": "string"]
            )
          ]
        )
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    let prompt = reloaded.phases[0].elsePhases?.first?.prompt ?? "<nil>"
    #expect(
      prompt == "Current scores: {scoreboard}\nWhat is your strategy?"
        || prompt == "Current scores: {scoreboard}\nWhat is your strategy?\n",
      "prompt: \(prompt.debugDescription), yaml:\n\(yaml)"
    )
  }
}
