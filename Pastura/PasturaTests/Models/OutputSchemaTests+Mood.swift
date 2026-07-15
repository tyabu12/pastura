import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `OutputSchemaTests` (type_body_length cap). Per
// `.claude/rules/testing.md`, this is an `extension` of the existing suite —
// NOT a new `@Suite` (a second suite would run in parallel against the same
// shared state). Pins the mood opt-in field's (#913) interaction with field
// ordering and the streaming thought-field resolver.
extension OutputSchemaTests {

  // A `mood`-opting phase: `mood` is an unknown key, so it sorts into the
  // alphabetical tail *after* the `inner_thought` secondary — giving the
  // intended `statement → inner_thought → mood` generation order without
  // registering `mood` in `knownSecondaryKeys`. Pins that the opt-in field
  // never displaces the primary/secondary UX ordering.
  @Test("mood opt-in field orders after inner_thought (unknown-tail)")
  func moodOrdersAfterInnerThought() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: [
            "mood": "string", "statement": "string", "inner_thought": "string"
          ])))
    #expect(schema.fields.map(\.name) == ["statement", "inner_thought", "mood"])
  }

  // A `{statement, mood}` phase must NOT surface `mood` as the live THINKING
  // field: `mood` is deliberately absent from `knownSecondaryKeys`, so
  // `thoughtFieldName` stays nil. Guards against a future edit adding `mood`
  // to the secondary set, which would route the opt-in mood value into the
  // streaming thought display and desync `ScenarioConventions.thoughtField`.
  @Test("mood is never the thought field (not a secondary key)")
  func thoughtFieldNameNilForStatementMood() throws {
    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["statement": "string", "mood": "string"])))
    #expect(schema.thoughtFieldName == nil)
  }
}
