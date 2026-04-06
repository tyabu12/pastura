import Foundation
import Testing

@testable import Pastura

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
}
