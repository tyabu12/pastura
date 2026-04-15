import Foundation
import Testing

@testable import Pastura

struct CodePhaseEventPayloadTests {
  private func roundTrip(_ payload: CodePhaseEventPayload) throws -> CodePhaseEventPayload {
    let data = try JSONEncoder().encode(payload)
    return try JSONDecoder().decode(CodePhaseEventPayload.self, from: data)
  }

  @Test func eliminationRoundTrip() throws {
    let original = CodePhaseEventPayload.elimination(agent: "Alice", voteCount: 3)
    #expect(try roundTrip(original) == original)
  }

  @Test func scoreUpdateRoundTrip() throws {
    let original = CodePhaseEventPayload.scoreUpdate(scores: [
      "Alice": 2, "Bob": -1, "Charlie": 0
    ])
    #expect(try roundTrip(original) == original)
  }

  @Test func summaryRoundTrip() throws {
    let original = CodePhaseEventPayload.summary(text: "Round 1 ended. お疲れさま。")
    #expect(try roundTrip(original) == original)
  }

  @Test func voteResultsRoundTrip() throws {
    let original = CodePhaseEventPayload.voteResults(
      votes: ["Alice": "Bob", "Bob": "Alice", "Charlie": "Bob"],
      tallies: ["Alice": 1, "Bob": 2]
    )
    #expect(try roundTrip(original) == original)
  }

  @Test func pairingResultRoundTrip() throws {
    let original = CodePhaseEventPayload.pairingResult(
      agent1: "Alice", action1: "cooperate",
      agent2: "Bob", action2: "betray"
    )
    #expect(try roundTrip(original) == original)
  }

  @Test func assignmentRoundTrip() throws {
    let original = CodePhaseEventPayload.assignment(agent: "Alice", value: "wolf")
    #expect(try roundTrip(original) == original)
  }

  @Test func differentCasesAreNotEqual() {
    let a = CodePhaseEventPayload.summary(text: "hello")
    let b = CodePhaseEventPayload.elimination(agent: "hello", voteCount: 1)
    #expect(a != b)
  }
}
