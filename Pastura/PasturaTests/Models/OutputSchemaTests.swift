import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct OutputSchemaTests {

  // MARK: - Field ordering (Critic Axis 2 — load-bearing for streaming UX)

  @Test("primary-first ordering: statement before inner_thought")
  func primaryBeforeSecondary_statement() throws {
    // word_wolf / target_score_race speak_all schema
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["inner_thought": "string", "statement": "string"])))
    #expect(schema.fields.map(\.name) == ["statement", "inner_thought"])
  }

  @Test("primary-first ordering: vote before reason")
  func primaryBeforeSecondary_vote() throws {
    // word_wolf / target_score_race / bokete vote schema
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .vote, prompt: "…",
          outputSchema: ["reason": "string", "vote": "string"])))
    #expect(schema.fields.map(\.name) == ["vote", "reason"])
  }

  @Test("primary-first ordering: action before inner_thought (choose)")
  func primaryBeforeSecondary_action() throws {
    // prisoners_dilemma choose schema
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .choose, prompt: "…",
          outputSchema: ["inner_thought": "string", "action": "string"],
          options: ["cooperate", "betray"])))
    #expect(schema.fields.map(\.name) == ["action", "inner_thought"])
  }

  @Test("input order swap yields identical field order (stability)")
  func inputOrderSwapIsStable() throws {
    let forward = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["statement": "string", "inner_thought": "string"])))
    let reversed = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["inner_thought": "string", "statement": "string"])))
    #expect(forward.fields.map(\.name) == reversed.fields.map(\.name))
  }

  @Test("unknown keys sort alphabetically after secondary keys")
  func unknownKeysAfterSecondary() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: [
            "zeta": "string", "statement": "string",
            "alpha": "string", "inner_thought": "string"
          ])))
    #expect(
      schema.fields.map(\.name)
        == ["statement", "inner_thought", "alpha", "zeta"])
  }

  // MARK: - Choice marker for choose.options

  @Test("choose with options marks the action field as .choice")
  func chooseOptionsBecomesChoice() throws {
    // `.choice` is a payload-free marker (no option strings) — the
    // options are NOT enumerated into the grammar (model-agnostic crash
    // safety, #599). It signals "author-fixed token, exclude from
    // language detection" only.
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .choose, prompt: "…",
          outputSchema: ["action": "string", "inner_thought": "string"],
          options: ["cooperate", "betray"])))
    let actionField = try #require(schema.fields.first { $0.name == "action" })
    #expect(actionField.kind == .choice)
    let thoughtField = try #require(
      schema.fields.first { $0.name == "inner_thought" })
    #expect(thoughtField.kind == .string)
  }

  @Test("regression #599: choose with CJK / hostile options yields .choice, never enumeration")
  func chooseDangerousOptionsBecomeChoice() throws {
    // `from(phase:)` must not carry option strings anywhere. Choose
    // options with CJK or GBNF-hostile chars (which previously enumerated
    // into the grammar and crashed/aborted) produce a payload-free
    // `.choice` marker with no validation/throw at the Models layer.
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .choose, prompt: "…",
          outputSchema: ["action": "string"],
          options: ["協力", "裏切り", #"a"b"#])))
    let actionField = try #require(schema.fields.first { $0.name == "action" })
    #expect(actionField.kind == .choice)
  }

  @Test("choose without options keeps action as plain string")
  func chooseWithoutOptionsIsString() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .choose, prompt: "…",
          outputSchema: ["action": "string", "inner_thought": "string"],
          options: nil)))
    let actionField = try #require(schema.fields.first { $0.name == "action" })
    #expect(actionField.kind == .string)
  }

  @Test("non-choose phases never produce .choice even with options-shaped data")
  func speakPhaseIgnoresOptions() throws {
    // Defensive: speak_all should never get .choice even if options accidentally present
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["statement": "string", "inner_thought": "string"],
          options: ["a", "b"])))
    for field in schema.fields {
      #expect(field.kind == .string)
    }
  }

  // MARK: - nil / edge cases

  @Test("nil outputSchema returns nil")
  func nilSchemaReturnsNil() {
    let phase = Phase(type: .speakAll, prompt: "…", outputSchema: nil)
    #expect(OutputSchema.from(phase: phase) == nil)
  }

  @Test("empty outputSchema returns nil")
  func emptySchemaReturnsNil() {
    let phase = Phase(type: .speakAll, prompt: "…", outputSchema: [:])
    #expect(OutputSchema.from(phase: phase) == nil)
  }

  @Test("code phase (score_calc) with no schema returns nil")
  func codePhaseReturnsNil() {
    let phase = Phase(type: .scoreCalc, logic: .prisonersDilemma)
    #expect(OutputSchema.from(phase: phase) == nil)
  }

  // MARK: - thoughtFieldName (#609)

  @Test("vote schema's thought field is reason")
  func thoughtFieldNameForVoteIsReason() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .vote, prompt: "…",
          outputSchema: ["vote": "string", "reason": "string"])))
    #expect(schema.thoughtFieldName == "reason")
  }

  @Test("speak schema's thought field is inner_thought")
  func thoughtFieldNameForSpeakIsInnerThought() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["statement": "string", "inner_thought": "string"])))
    #expect(schema.thoughtFieldName == "inner_thought")
  }

  @Test("schema with no secondary key has nil thought field")
  func thoughtFieldNameNilWhenNoSecondaryKey() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .vote, prompt: "…",
          outputSchema: ["vote": "string"])))
    #expect(schema.thoughtFieldName == nil)
  }

  // Degenerate both-present case (presets author one secondary key per
  // phase): `inner_thought` wins by knownSecondaryKeys priority order.
  @Test("both secondary keys present resolves to inner_thought by priority")
  func thoughtFieldNamePrefersInnerThoughtWhenBoth() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: [
            "statement": "string", "inner_thought": "string", "reason": "string"
          ])))
    #expect(schema.thoughtFieldName == "inner_thought")
  }

  // MARK: - Codable

  @Test("Codable round-trip preserves fields and order")
  func codableRoundTrip() throws {
    let original = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .choose, prompt: "…",
          outputSchema: ["action": "string", "inner_thought": "string"],
          options: ["cooperate", "betray"])))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(OutputSchema.self, from: data)
    #expect(decoded == original)
    #expect(decoded.fields.map(\.name) == ["action", "inner_thought"])
  }

  // MARK: - Consistency with PartialOutputExtractor.primaryKeys

  @Test(
    "OutputSchema primary key list is a superset of PartialOutputExtractor.primaryKeys")
  func primaryKeySuperset() {
    // Streaming UX invariant: every primary key the extractor recognises
    // must be treated as primary by OutputSchema, otherwise the grammar
    // could force it to stream later than inner_thought.
    for key in PartialOutputExtractor.primaryKeys {
      #expect(
        OutputSchema.knownPrimaryKeys.contains(key),
        "\(key) is a streaming-UX primary key but not in OutputSchema.knownPrimaryKeys"
      )
    }
  }

  // MARK: - All preset shapes

  @Test("all preset LLM phases factory without crash")
  func allPresetShapes() throws {
    struct Case {
      let label: String
      let schema: [String: String]
      let type: PhaseType
      let options: [String]?
      let expectedOrder: [String]
    }
    let cases: [Case] = [
      // bokete
      .init(
        label: "bokete.speakAll",
        schema: ["statement": "string", "inner_thought": "string"],
        type: .speakAll, options: nil,
        expectedOrder: ["statement", "inner_thought"]),
      .init(
        label: "bokete.vote",
        schema: ["vote": "string", "reason": "string"],
        type: .vote, options: nil,
        expectedOrder: ["vote", "reason"]),
      // prisoners_dilemma
      .init(
        label: "prisoners_dilemma.speakAll",
        schema: ["statement": "string", "inner_thought": "string"],
        type: .speakAll, options: nil,
        expectedOrder: ["statement", "inner_thought"]),
      .init(
        label: "prisoners_dilemma.choose",
        schema: ["action": "string", "inner_thought": "string"],
        type: .choose, options: ["cooperate", "betray"],
        expectedOrder: ["action", "inner_thought"]),
      // target_score_race / word_wolf
      .init(
        label: "target_score_race.speakAll",
        schema: ["statement": "string", "inner_thought": "string"],
        type: .speakAll, options: nil,
        expectedOrder: ["statement", "inner_thought"]),
      .init(
        label: "target_score_race.vote",
        schema: ["vote": "string", "reason": "string"],
        type: .vote, options: nil,
        expectedOrder: ["vote", "reason"])
    ]
    for testCase in cases {
      let phase = Phase(
        type: testCase.type, prompt: "…",
        outputSchema: testCase.schema, options: testCase.options)
      let schema = try #require(
        OutputSchema.from(phase: phase),
        "\(testCase.label): factory returned nil")
      #expect(
        schema.fields.map(\.name) == testCase.expectedOrder,
        "\(testCase.label): order mismatch")
    }
  }
}
