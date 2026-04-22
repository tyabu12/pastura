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
      "declaration": "Let's work together",
      "boke": "That's funny",
      "reason": "Because they're trustworthy"
    ])

    #expect(output.statement == "Hello")
    #expect(output.vote == "Alice")
    #expect(output.action == "cooperate")
    #expect(output.innerThought == "I should cooperate")
    #expect(output.declaration == "Let's work together")
    #expect(output.boke == "That's funny")
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
}
