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

  /// Serializes a scenario whose only multi-line field is `description`
  /// (single-line personas), so an emitted `description: |-` block is
  /// unambiguously attributable to the value under test.
  private func serializeWithDescription(_ description: String) -> String {
    serializer.serialize(
      Scenario(
        id: "edge", name: "Edge", description: description, language: "en",
        agentCount: 2, rounds: 1, context: "A single-line context.",
        personas: [
          Persona(name: "Alice", description: "A strategist"),
          Persona(name: "Bob", description: "An optimist")
        ],
        phases: [Phase(type: .speakAll, prompt: "Speak.", outputSchema: ["statement": "string"])]
      ))
  }

  // Block-unsafe multi-line descriptions (#752, surfaced in code review): a
  // first line with leading whitespace makes a literal block *unparseable* —
  // without the self-verifying gate the scenario would be unloadable after a
  // save — while CRLF and a trailing newline don't survive a `|-` block
  // verbatim. The self-verify must fall back to the inline (escaped) path, which
  // round-trips any string (#749). Regression guard: revert the gate and the
  // leading-whitespace case fails the inline-fallback assertion (and would
  // throw on reload); CRLF / trailing-newline fail the round-trip equality.
  @Test func blockUnsafeDescriptionsFallBackToInline() throws {
    let mustFallBack = [
      "  indented first line.\nsecond line.",  // leading whitespace → unparseable block
      "first line.\r\nsecond line.",  // CRLF → \r normalized by a block
      "ends with newline.\nlast line.\n"  // trailing newline → stripped by `|-`
    ]
    for description in mustFallBack {
      let yaml = serializeWithDescription(description)
      #expect(
        !yaml.contains("description: |-"),
        "expected inline fallback for \(description.debugDescription)")
      #expect(
        try loader.load(yaml: yaml).description == description,
        "round-trip failed for \(description.debugDescription)")
    }
  }

  // The self-verifying gate adapts to the actual Yams parser: a multi-line value
  // with a whitespace-only interior line round-trips through a literal block in
  // libYAML, so the gate keeps the readable block form. Whichever form it picks,
  // the value must round-trip exactly.
  @Test func blockSafeEdgeDescriptionRoundTrips() throws {
    let description = "first line.\n   \nthird line."  // whitespace-only interior line
    let yaml = serializeWithDescription(description)
    #expect(try loader.load(yaml: yaml).description == description)
  }
}
