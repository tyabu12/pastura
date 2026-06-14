import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct TurnOutputTests {
  @Test func typedAccessorsReturnCorrectValues() {
    let output = TurnOutput(fields: [
      "statement": "Hello",
      "vote": "Alice",
      "action": "cooperate",
      "inner_thought": "I should cooperate",
      "reason": "Because they're trustworthy"
    ])

    #expect(output.statement == "Hello")
    #expect(output.vote == "Alice")
    #expect(output.action == "cooperate")
    #expect(output.innerThought == "I should cooperate")
    #expect(output.reason == "Because they're trustworthy")
  }

  @Test func typedAccessorsReturnNilForMissingKeys() {
    let output = TurnOutput(fields: ["action": "betray"])

    #expect(output.statement == nil)
    #expect(output.vote == nil)
    #expect(output.innerThought == nil)
  }

  @Test func requireReturnsValueForPresentKey() throws {
    let output = TurnOutput(fields: ["action": "cooperate"])
    let value = try output.require("action")
    #expect(value == "cooperate")
  }

  @Test func requireThrowsForMissingKey() {
    let output = TurnOutput(fields: [:])
    #expect(throws: TurnOutputError.missingField("action")) {
      try output.require("action")
    }
  }

  @Test func requireThrowsForEmptyValue() {
    let output = TurnOutput(fields: ["action": ""])
    #expect(throws: TurnOutputError.missingField("action")) {
      try output.require("action")
    }
  }

  @Test func codableRoundTrip() throws {
    let original = TurnOutput(fields: [
      "action": "betray",
      "inner_thought": "Strategic move"
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TurnOutput.self, from: data)
    #expect(decoded == original)
  }

  // MARK: - rawText (#194)

  // rawText is the pre-parse LLM emission, populated by JSONResponseParser via
  // LLMCaller. It travels with the parsed TurnOutput so persistTurnRecord can
  // store it in TurnRecord.rawOutput (audit trail for A2 repair work in #194).
  @Test func rawTextStoresProvidedValue() {
    let raw = #"{"statement": "hi"}"#
    let output = TurnOutput(fields: ["statement": "hi"], rawText: raw)
    #expect(output.rawText == raw)
  }

  @Test func rawTextDefaultsToNilWhenOmitted() {
    let output = TurnOutput(fields: ["statement": "hi"])
    #expect(output.rawText == nil)
  }

  // rawText must NOT appear in encoded JSON. parsedOutputJSON column would
  // otherwise duplicate the raw text already stored in TurnRecord.rawOutput,
  // doubling per-turn DB write size (~1-2 KB per Gemma turn).
  @Test func rawTextIsExcludedFromEncodedJSON() throws {
    let output = TurnOutput(
      fields: ["statement": "hi"],
      rawText: "raw stream content here")
    let data = try JSONEncoder().encode(output)
    let json = String(data: data, encoding: .utf8) ?? ""
    #expect(!json.contains("rawText"))
    #expect(!json.contains("raw stream content here"))
  }

  // Backward-compat: pre-PR persisted `parsedOutputJSON` blobs (i.e. JSON
  // without a "rawText" key) must decode cleanly with rawText == nil.
  @Test func decodesPreviousFormatWithoutRawText() throws {
    let preFormatJSON = #"{"fields": {"statement": "hello"}}"#
    let data = preFormatJSON.data(using: .utf8) ?? Data()
    let decoded = try JSONDecoder().decode(TurnOutput.self, from: data)
    #expect(decoded.fields["statement"] == "hello")
    #expect(decoded.rawText == nil)
  }

  // Equatable compares semantic content (fields), not provenance metadata
  // (rawText). Two outputs parsed from different raw streams that produced
  // the same fields are domain-equal.
  @Test func equatableIgnoresRawText() {
    let withRawA = TurnOutput(fields: ["k": "v"], rawText: "raw1")
    let withRawB = TurnOutput(fields: ["k": "v"], rawText: "raw2")
    let withoutRaw = TurnOutput(fields: ["k": "v"], rawText: nil)
    #expect(withRawA == withRawB)
    #expect(withRawA == withoutRaw)
  }

  // MARK: - primaryText (#609)

  // Vote primary text is the bare arrow form `→ <voted>`. The vote `reason`
  // is the vote-phase private-thought field (the equivalent of speak's
  // `inner_thought`) and is surfaced via `secondaryText(for:)` / the THINKING
  // section — NOT appended inline to the primary text. Regression guard:
  // if a refactor re-appends `(reason)` here, the vote row would double-show
  // the reason (inline + THINKING).
  @Test func votePrimaryTextOmitsReason() {
    let output = TurnOutput(fields: ["vote": "Alice", "reason": "信頼できる"])
    #expect(output.primaryText(for: .vote) == "→ Alice")
  }

  @Test func votePrimaryTextWithoutReason() {
    let output = TurnOutput(fields: ["vote": "Bob"])
    #expect(output.primaryText(for: .vote) == "→ Bob")
  }

  @Test func speakPrimaryTextIsStatement() {
    let output = TurnOutput(fields: ["statement": "Hello"])
    #expect(output.primaryText(for: .speakAll) == "Hello")
  }

  // MARK: - secondaryText (#609)

  // `secondaryText(for:)` resolves the phase's private-thought field via
  // `ScenarioConventions.thoughtField(for:)`: `reason` for vote, `inner_thought`
  // otherwise. Phase-aware (not a blind `innerThought ?? reason`) so a stray
  // `reason` on a speak/choose output never leaks into the THINKING section,
  // and a vote's `reason` is never silently dropped in favour of an
  // `inner_thought` that vote schemas don't author.
  @Test func voteSecondaryTextIsReason() {
    let output = TurnOutput(fields: ["vote": "Alice", "reason": "信頼できる"])
    #expect(output.secondaryText(for: .vote) == "信頼できる")
  }

  @Test func speakSecondaryTextIsInnerThought() {
    let output = TurnOutput(fields: ["statement": "Hi", "inner_thought": "本音"])
    #expect(output.secondaryText(for: .speakAll) == "本音")
  }

  @Test func chooseSecondaryTextIsInnerThought() {
    let output = TurnOutput(fields: ["action": "cooperate", "inner_thought": "戦略"])
    #expect(output.secondaryText(for: .choose) == "戦略")
  }

  // Precedence with BOTH fields present (test-fixture shape; presets author
  // only one per phase). Vote reads `reason`; speak reads `inner_thought` —
  // neither cross-leaks.
  @Test func secondaryTextPrefersPhaseFieldWhenBothPresent() {
    let output = TurnOutput(fields: [
      "vote": "Alice",
      "inner_thought": "private calc",
      "reason": "stated reason"
    ])
    #expect(output.secondaryText(for: .vote) == "stated reason")
    #expect(output.secondaryText(for: .speakAll) == "private calc")
  }

  // Code phases have no private-thought field.
  @Test func secondaryTextNilForCodePhase() {
    let output = TurnOutput(fields: ["inner_thought": "x", "reason": "y"])
    #expect(output.secondaryText(for: .scoreCalc) == nil)
  }
}
