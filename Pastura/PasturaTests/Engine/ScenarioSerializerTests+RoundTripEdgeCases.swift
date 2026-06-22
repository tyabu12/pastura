import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `ScenarioSerializerTests` (file_length cap). Per
// `.claude/rules/testing.md`, extend the suite struct rather than declaring a
// new `@Suite` (which would run in parallel and race shared state).
extension ScenarioSerializerTests {

  // `description` and `extraData` strings render through `yamlScalar` (inline),
  // NOT the block-scalar path that `context`/`prompt`/`template` use. Before
  // the #749 quoting fix, an embedded newline in one of these folded to a space
  // (or corrupted) on reload. `assertScenariosEqual` does not compare
  // `description`, so assert it explicitly here.
  @Test func roundTripMultilineDescriptionAndExtraDataNewline() throws {
    let scenario = Scenario(
      id: "roundtrip_inline_edge",
      name: "Edge",
      description: "First line of the brief.\nSecond line with detail.",
      language: "en",
      agentCount: 2,
      rounds: 1,
      context: "A single-line context.",
      personas: [
        Persona(name: "Alice", description: "A strategist"),
        Persona(name: "Bob", description: "An optimist")
      ],
      phases: [
        Phase(type: .speakAll, prompt: "Speak.", outputSchema: ["statement": "string"])
      ],
      extraData: [
        "note": .string("line one\nline two"),
        "topics": .array(["plain", "trailing space "])
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    #expect(reloaded.description == scenario.description)
    #expect(reloaded.extraData["note"] == .string("line one\nline two"))
    #expect(reloaded.extraData["topics"] == .array(["plain", "trailing space "]))
  }
}
