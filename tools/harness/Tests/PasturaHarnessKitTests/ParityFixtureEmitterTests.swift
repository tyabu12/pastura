import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

/// `.serialized` because every emitter case constructs a `SimulationRunner`,
/// which spawns `Task` + `AsyncStream`; concurrent teardown crashes the test
/// process (`.claude/rules/swift-testing-parallelism.md`).
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ParityFixtureEmitterTests {

  // MARK: - RecordingResponder

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

    #expect(first.contains("アオイ"))
    #expect(second.contains("ハルト"))
  }

  @Test("an override replaces the derived answer at exactly its call index")
  func responderHonoursOverrideIndex() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let responder = RecordingResponder(personas: ["Alice"], overrides: [1: #"{"statement": ""}"#])

    _ = try await responder.generate(system: "", user: "", schema: schema)
    let overridden = try await responder.generate(system: "", user: "", schema: schema)
    let after = try await responder.generate(system: "", user: "", schema: schema)

    #expect(overridden == #"{"statement": ""}"#)
    #expect(!after.contains("\"\""))
    #expect(responder.callCount == 3)
    #expect(responder.recordedResponses.count == 3)
  }

  // MARK: - Determinism

  @Test("two runs of the same spec produce byte-identical fixtures")
  func emitterIsDeterministic() async throws {
    guard let spec = ParityFixtureEmitter.specs.first else {
      Issue.record("no fixture specs declared")
      return
    }
    let first = try await ParityFixtureEmitter.run(spec)
    let second = try await ParityFixtureEmitter.run(spec)

    // The reason this can pass at all: `EventLineMapper` takes `t` / `attempt`
    // as parameters, and `ParityFixtureEmitter.normalize` zeroes the one
    // measured quantity a payload carries. Remove either and this reddens —
    // `inferenceCompleted.durationSeconds` was observed varying per call before
    // the normalization landed.
    #expect(first == second)
  }

  @Test("no transcript line carries a measured duration")
  func transcriptCarriesNoMeasuredDuration() async throws {
    guard let spec = ParityFixtureEmitter.specs.first else {
      Issue.record("no fixture specs declared")
      return
    }
    let fixture = try await ParityFixtureEmitter.run(spec)

    // Asserted on the value, not on the key's absence: the key is legitimately
    // present, and a check for absence would pass for the wrong reason if the
    // event stopped being emitted at all.
    let durations = fixture.transcript.filter { $0.contains("\"duration_seconds\"") }
    #expect(
      !durations.isEmpty, "no inference_completed line — the assertion below would be vacuous")
    #expect(durations.allSatisfy { $0.contains("\"duration_seconds\":0") })
  }

  @Test("the run drives the engine end to end")
  func emitterProducesACompleteRun() async throws {
    guard let spec = ParityFixtureEmitter.specs.first else {
      Issue.record("no fixture specs declared")
      return
    }
    let fixture = try await ParityFixtureEmitter.run(spec)

    #expect(fixture.callCount == fixture.responses.count)
    #expect(fixture.transcript.contains { $0.contains("\"simulation_completed\"") })
    #expect(fixture.scenarioJSON.contains("target_score_race"))
  }

  // MARK: - Raw-string safety guard

  @Test("a payload Kotlin would interpolate is rejected at generation time")
  func rawStringGuardRejectsInterpolation() throws {
    // Negative control: the guard's success path proves nothing, so construct
    // the thing it claims to catch and confirm it fires.
    let unsafe = ParityFixtureEmitter.Fixture(
      name: "unsafe", purpose: "control", scenarioJSON: #"{"id": "$injected"}"#,
      responses: [], transcript: [], callCount: 0)

    #expect(throws: ParityFixtureError.self) {
      _ = try ParityFixtureEmitter.kotlinSource(from: [unsafe])
    }
  }

  @Test("a payload closing the raw string early is rejected")
  func rawStringGuardRejectsTripleQuote() throws {
    let unsafe = ParityFixtureEmitter.Fixture(
      name: "unsafe", purpose: "control", scenarioJSON: "{}",
      responses: ["\"\"\""], transcript: [], callCount: 0)

    #expect(throws: ParityFixtureError.self) {
      _ = try ParityFixtureEmitter.kotlinSource(from: [unsafe])
    }
  }

  @Test("a safe fixture renders")
  func rawStringGuardAcceptsSafePayload() throws {
    let safe = ParityFixtureEmitter.Fixture(
      name: "safe", purpose: "control", scenarioJSON: "{}",
      responses: [#"{"statement": "ok"}"#], transcript: ["{}"], callCount: 1)

    let source = try ParityFixtureEmitter.kotlinSource(from: [safe])
    #expect(source.contains("internal val safe: Fixture"))
    #expect(source.contains("callCount = 1"))
  }
}
