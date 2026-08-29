import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

/// ``RecordingResponder``'s suspend-schedule seam (ADR-023 Stage 4 S5, #1625
/// item 1) — split from `RecordingResponderTests` by subject, matching that
/// file's own split from `ParityFixtureEmitterTests`.
@Suite(.timeLimit(.minutes(1)))
struct RecordingResponderTestsSuspend {

  @Test("a scheduled index throws suspended N times, then answers, without recording a suspend")
  func scheduledSuspendsPrecedeTheAnswer() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    // Response index 1 (the second call) is preceded by two suspend cycles.
    let responder = RecordingResponder(personas: ["Alice"], suspendBeforeResponse: [1: 2])

    let first = try await responder.generate(system: "", user: "", schema: schema)

    // The two suspend cycles for index 1, then the index-1 answer itself.
    for _ in 0..<2 {
      await #expect(throws: LLMError.suspended) {
        _ = try await responder.generate(system: "", user: "", schema: schema)
      }
    }
    let second = try await responder.generate(system: "", user: "", schema: schema)

    #expect(first == #"{"statement": "statement 0"}"#)
    // Derived from `state.responses.count`, which a suspend never advances —
    // so the answer that finally lands at index 1 is still derived as index 1,
    // not index 3.
    #expect(second == #"{"statement": "statement 1"}"#)
    // Every backend call: 2 suspends + 2 answers.
    #expect(responder.callCount == 4)
    // Suspends are excluded — only the two real answers are recorded.
    #expect(responder.recordedResponses == [first, second])
    #expect(responder.remainingSuspends == 0)
  }

  @Test("a suspended call does not advance the vote rotation")
  func suspendedCallDoesNotAdvanceVoteRotation() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "vote", kind: .string)])
    // One suspend cycle before the first vote call (index 0).
    let responder = RecordingResponder(
      personas: ["アオイ", "ハルト", "リオ"], suspendBeforeResponse: [0: 1])

    await #expect(throws: LLMError.suspended) {
      _ = try await responder.generate(system: "", user: "", schema: schema)
    }
    // Re-issued at the same index: if the suspend had advanced `voteCallCount`,
    // this would vote for "リオ" (the second rotation slot) instead of "ハルト"
    // (the first) — the same rotation `responderResolvesVoteToPersona` pins.
    let reissued = try await responder.generate(system: "", user: "", schema: schema)

    #expect(reissued.contains("ハルト"))
    #expect(responder.callCount == 2)
    #expect(responder.recordedResponses == [reissued])
  }

  @Test("with no schedule, callCount equals recordedResponses.count")
  func noScheduleLeavesCallCountEqualToResponseCount() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let responder = RecordingResponder(personas: ["Alice"])

    for _ in 0..<3 {
      _ = try await responder.generate(system: "", user: "", schema: schema)
    }

    #expect(responder.callCount == responder.recordedResponses.count)
    #expect(responder.callCount == 3)
    #expect(responder.remainingSuspends == 0)
  }
}
