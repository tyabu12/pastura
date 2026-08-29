import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

/// The responder's own contract, split out of `ParityFixtureEmitterTests` when
/// that file crossed SwiftLint's `file_length` — these cases construct no
/// `SimulationRunner`, so they need neither `.serialized` nor a repo-root
/// working directory, unlike every case left in the emitter suite.
@Suite(.timeLimit(.minutes(1)))
struct RecordingResponderTests {

  @Test("answers are derived from the schema, never from the prompt")
  func responderIgnoresPrompt() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let shortPrompted = RecordingResponder(personas: ["Alice"])
    let longPrompted = RecordingResponder(personas: ["Alice"])

    let fromShortPrompt = try await shortPrompted.generate(system: "s", user: "u", schema: schema)
    let fromLongPrompt = try await longPrompted.generate(
      system: "a much longer system prompt", user: "a much longer user prompt", schema: schema)

    // The guard this defends: `PromptBuilder.formatScoreboard` orders and
    // collapses keys differently in the two engines, so a prompt-keyed
    // responder would hand them different scripts and report the difference as
    // an engine divergence.
    #expect(fromShortPrompt == fromLongPrompt)
  }

  @Test("a vote field resolves to a persona the tally can count")
  func responderResolvesVoteToPersona() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "vote", kind: .string)])
    let responder = RecordingResponder(personas: ["アオイ", "ハルト", "リオ"])

    let first = try await responder.generate(system: "", user: "", schema: schema)
    let second = try await responder.generate(system: "", user: "", schema: schema)

    // Offset by one (see `RecordingResponder.value(for:)`), so call 0 votes for
    // persona 1 rather than persona 0 — which for a real scenario is the
    // difference between a counted vote and a self-vote `exclude_self` drops.
    #expect(first.contains("ハルト"))
    #expect(second.contains("リオ"))
  }

  @Test("an override replaces the derived answer at exactly its call index")
  func responderHonoursOverrideIndex() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let responder = RecordingResponder(personas: ["Alice"], overrides: [1: #"{"statement": ""}"#])

    _ = try await responder.generate(system: "", user: "", schema: schema)
    let overridden = try await responder.generate(system: "", user: "", schema: schema)
    let after = try await responder.generate(system: "", user: "", schema: schema)

    #expect(overridden == #"{"statement": ""}"#)
    // Asserted as the exact value, not as "not empty": the latter passes for any
    // non-empty payload, including a wrongly-indexed one, and would pass
    // vacuously if `derive` changed shape. This pins that the override applied
    // at exactly index 1 and the derivation resumed at call index 2.
    #expect(after == #"{"statement": "statement 2"}"#)
    #expect(responder.callCount == 3)
    #expect(responder.recordedResponses.count == 3)
  }

  @Test("the choice schedule covers every ordered option pair within n² pairs")
  func responderChoiceScheduleCoversEveryCombination() async throws {
    // The unit-level cover for the schedule. The fixture-level one is
    // `expectEveryPayoffRowFires` on `prisonersDilemmaNominal`, which only sees
    // the combinations that scenario's pair count reaches; this one pins the
    // enumeration itself, independent of any scenario.
    //
    // The contract, stated where the responder cannot state it for itself:
    // `ChooseHandler.executeRoundRobin` issues a pairing's two members as two
    // consecutive calls, so 8 calls are 4 pairs, and for n = 2 options all four
    // ordered combinations must appear — that is what makes every row of a
    // `pairwise_payoff` table fire. A `k % n` schedule passes a "some pairing
    // happened" check and fails this one, producing only (A,B) and (B,A).
    let choice = OutputSchema(fields: [OutputSchema.Field(name: "action", kind: .choice)])
    let responder = RecordingResponder(personas: ["Alice"], choiceOptions: ["A", "B"])

    for _ in 0..<8 {
      _ = try await responder.generate(system: "", user: "", schema: choice)
    }
    let answers = responder.recordedResponses
    try #require(answers.count == 8)

    // Every answer is on-menu — an off-menu one is dropped by `validateAction`,
    // which is the failure this whole change exists to prevent.
    #expect(answers.allSatisfy { $0 == #"{"action": "A"}"# || $0 == #"{"action": "B"}"# })
    let pairs = stride(from: 0, to: answers.count, by: 2).map { index in
      [answers[index], answers[index + 1]]
    }
    // Order-insensitive: the schedule's job is coverage, not a particular
    // sequence, and pinning the sequence would redden on a harmless reordering.
    let expected: Set<[String]> = [
      [#"{"action": "A"}"#, #"{"action": "A"}"#],
      [#"{"action": "B"}"#, #"{"action": "A"}"#],
      [#"{"action": "A"}"#, #"{"action": "B"}"#],
      [#"{"action": "B"}"#, #"{"action": "B"}"#]
    ]
    #expect(Set(pairs) == expected)

    // A `.string` field is untouched by any of this, and still keyed on the
    // GLOBAL call index — asserted as the exact value so a schedule that leaked
    // into the string path cannot pass.
    let plain = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let after = try await responder.generate(system: "", user: "", schema: plain)
    #expect(after == #"{"statement": "statement 8"}"#)
  }

  @Test("an empty option list leaves the choice field on the call-indexed string")
  func responderFallsBackWhenNoOptionsAreKnown() async throws {
    // The options-less `choose` carve-out: `validateAction` passes a raw action
    // through unchanged there, so the derived string is correct rather than a
    // silent drop. Without this case the fallback branch is untested.
    let choice = OutputSchema(fields: [OutputSchema.Field(name: "action", kind: .choice)])
    let responder = RecordingResponder(personas: ["Alice"])

    let first = try await responder.generate(system: "", user: "", schema: choice)

    #expect(first == #"{"action": "action 0"}"#)
  }
}
