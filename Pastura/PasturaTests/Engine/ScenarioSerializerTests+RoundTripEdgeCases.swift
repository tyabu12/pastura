import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `ScenarioSerializerTests` (file_length cap). Per
// `.claude/rules/testing.md`, extend the suite struct rather than declaring a
// new `@Suite` (which would run in parallel and race shared state).
extension ScenarioSerializerTests {

  // Round-trip-correctness guard for the inline-scalar fields, independent of
  // output *style*. `extraData` strings still render through `yamlScalar`
  // (inline) — only `description` / persona `description` moved to the
  // block-scalar path (#752); their multi-line *format* is asserted separately
  // in `multilineDescriptionsSerializeAsBlockScalars`. Before the #749 quoting
  // fix, an embedded newline in any of these folded to a space (or corrupted)
  // on reload. `assertScenariosEqual` does not compare `description`, so assert
  // it explicitly here.
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

  // Readability follow-up to #749 (#752): a multi-line `description` or persona
  // `description` serializes as a `|` literal block (matching the
  // `context`/`prompt`/`template` fields) rather than an escaped one-liner,
  // while single-line values stay inline. Asserts the *output format* — the
  // round-trip correctness it relies on is covered above and by the preset
  // suites.
  @Test func multilineDescriptionsSerializeAsBlockScalars() throws {
    let scenario = Scenario(
      id: "block_scalar_desc",
      name: "Block",
      description: "First line of the brief.\nSecond line with detail.",
      language: "en",
      agentCount: 2,
      rounds: 1,
      context: "A single-line context.",
      personas: [
        Persona(name: "Alice", description: "Persona line one.\nPersona line two."),
        Persona(name: "Bob", description: "A single-line persona")
      ],
      phases: [
        Phase(type: .speakAll, prompt: "Speak.", outputSchema: ["statement": "string"])
      ]
    )

    let yaml = serializer.serialize(scenario)

    // Top-level multi-line description → strip-chomped literal block at indent 0
    // (marker at column 0, content indented two spaces). `|-` (not `|`) so the
    // no-trailing-newline value round-trips verbatim — clip `|` would append a
    // trailing newline.
    #expect(
      yaml.contains("description: |-\n  First line of the brief.\n  Second line with detail."))
    // Persona multi-line description → strip-chomped literal block nested under
    // the `  - name:` list item: marker at column 4, content at column 6.
    #expect(yaml.contains("    description: |-\n      Persona line one.\n      Persona line two."))
    // Single-line persona description stays inline (the block path must not
    // force `|-` on one-liners).
    #expect(yaml.contains("    description: A single-line persona\n"))

    // Round-trip stays correct through the block-scalar path.
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.description == scenario.description)
    #expect(reloaded.personas[0].description == scenario.personas[0].description)
    #expect(reloaded.personas[1].description == scenario.personas[1].description)
  }
}
