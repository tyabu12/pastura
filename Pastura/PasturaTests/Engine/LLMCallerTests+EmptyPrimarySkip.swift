import Foundation
import Testing

@testable import Pastura

/// ADR-021 § Amendment 2026-08-06 — `empty_field` exhaustion throws when the
/// phase's *declared* canonical primary is missing, and returns otherwise.
///
/// Sibling extension rather than a new `@Suite`: Swift Testing runs suites in
/// parallel and `.serialized` only orders within one, so a second suite would
/// race (`testing.md` § "Splitting a Suite Across Files"). The suite's
/// `.timeLimit(.minutes(1))` is inherited.
extension LLMCallerTests {

  private func speakSchema() -> OutputSchema {
    OutputSchema(fields: [
      OutputSchema.Field(name: "statement", kind: .string),
      OutputSchema.Field(name: "inner_thought", kind: .string)
    ])
  }

  // MARK: - Clause 2: exhaustion throws (the positive case)

  /// The load-bearing test. Reverting the `if primaryMissing { throw }` leg in
  /// `LLMCaller.call` must turn this red — a suite that only pins the
  /// *returns* cases would stay green against a no-op implementation.
  @Test func exhaustedEmptyPrimaryThrowsWhenSchemaDeclaresIt() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "", "inner_thought": "thinking"}"#,
      #"{"statement": "", "inner_thought": "thinking"}"#,
      #"{"statement": "", "inner_thought": "thinking"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    await #expect(throws: SimulationError.retriesExhausted) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        phaseType: .speakAll,
        schema: speakSchema(),
        suspendController: SuspendController(),
        emitter: collector.emit
      )
    }
    #expect(mock.generateCallCount == 3, "throw lands on exhaustion, not early")
  }

  /// The `"..."` filler is the same defect as `""` — the model produced no
  /// content either way.
  @Test func exhaustedFillerPrimaryThrows() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "...", "inner_thought": "t"}"#,
      #"{"statement": "...", "inner_thought": "t"}"#,
      #"{"statement": "...", "inner_thought": "t"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    await #expect(throws: SimulationError.retriesExhausted) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        phaseType: .speakAll,
        schema: speakSchema(),
        suspendController: SuspendController(),
        emitter: collector.emit
      )
    }
  }

  /// A declared primary that is *absent* rather than empty. `hasEmptyFields`
  /// inspects values, not keys, so without the key-aware check this returned
  /// at attempt 0 and handed the handler a primary-less turn.
  @Test func exhaustedAbsentPrimaryThrows() async throws {
    let mock = MockLLMService(responses: [
      #"{"inner_thought": "thinking"}"#,
      #"{"inner_thought": "thinking"}"#,
      #"{"inner_thought": "thinking"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    await #expect(throws: SimulationError.retriesExhausted) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        phaseType: .speakAll,
        schema: speakSchema(),
        suspendController: SuspendController(),
        emitter: collector.emit
      )
    }
    #expect(
      mock.generateCallCount == 3,
      "an absent declared primary must also drive the retry, or the throw leg is unreachable")
  }

  // MARK: - Clause 1: the retry trigger keeps its all-fields scan

  /// Negative control AND the clause-1 pin in one: a delivered `statement`
  /// with an empty `inner_thought` still burns the full retry budget (so the
  /// narrowing did not silently shrink the *retry* trigger), and is still
  /// RETURNED at exhaustion rather than discarded.
  ///
  /// `generateCallCount == 3` is what disambiguates the two readings — under a
  /// primary-only retry trigger this would be 1.
  @Test func emptySecondaryRetriesThenReturnsAtExhaustion() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "delivered", "inner_thought": ""}"#,
      #"{"statement": "delivered", "inner_thought": ""}"#,
      #"{"statement": "delivered", "inner_thought": ""}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      schema: speakSchema(),
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == "delivered", "content the model DID produce is not discarded")
    #expect(mock.generateCallCount == 3, "the all-fields retry trigger is unchanged")
  }

  // MARK: - The two narrowings

  /// Backward compatibility. `validateForCommit` gates the canonical field at
  /// commit time only, so a pre-gate or ADR-020-imported scenario can omit it
  /// from `output:`. Keying on the phase type alone would make every turn of
  /// such a phase skip — three in a row trips `TurnFailureGate` and the
  /// scenario stops running at all.
  @Test func undeclaredCanonicalPrimaryStillReturns() async throws {
    let mock = MockLLMService(responses: [
      #"{"inner_thought": "only a secondary field is declared here"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      schema: OutputSchema(fields: [
        OutputSchema.Field(name: "inner_thought", kind: .string)
      ]),
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == nil)
    #expect(mock.generateCallCount == 1, "no retry, no throw — the rule is off for this schema")
  }

  /// Same carve-out, driven across the **whole** retry window: the secondary is
  /// empty too, so clause 1 retries to exhaustion and clause 2 has a final
  /// attempt to fire on — yet must not, because the canonical primary is
  /// undeclared. The sibling above returns at attempt 0 and so never reaches
  /// that leg; this is the shape a legacy scenario actually hits.
  /// Kotlin counterpart: `anUndeclaredCanonicalPrimaryStillReturnsAcrossTheFullRetryWindow`.
  @Test func undeclaredCanonicalPrimaryStillReturnsAtExhaustion() async throws {
    let empty = #"{"inner_thought": ""}"#
    let mock = MockLLMService(responses: [empty, empty, empty])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      schema: OutputSchema(fields: [
        OutputSchema.Field(name: "inner_thought", kind: .string)
      ]),
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement == nil)
    #expect(
      mock.generateCallCount == 3,
      "the empty secondary still drives the retry; only the skip rule is off")
  }

  /// The canonical primary is resolved from the PHASE TYPE, never from the
  /// schema. A `vote` phase that also declares `statement` must be judged on
  /// `vote`; resolving through `OutputSchema.knownPrimaryKeys` would find the
  /// non-empty `statement` and wrongly return.
  @Test func primaryLookupIsPhaseKeyedNotSchemaDerived() async throws {
    let strayStatement = #"{"vote": "", "statement": "a stray non-empty statement"}"#
    let mock = MockLLMService(responses: [strayStatement, strayStatement, strayStatement])
    try await mock.loadModel()

    let collector = EventCollector()
    await #expect(throws: SimulationError.retriesExhausted) {
      try await caller.call(
        llm: mock, system: "sys", user: "usr", agentName: "Alice",
        phaseType: .vote,
        schema: OutputSchema(fields: [
          OutputSchema.Field(name: "vote", kind: .string),
          OutputSchema.Field(name: "statement", kind: .string)
        ]),
        suspendController: SuspendController(),
        emitter: collector.emit
      )
    }
  }

  /// `narrate`'s schema is engine-fixed, so `primaryField(for: .narrate)` is
  /// `nil` and the rule cannot fire. Load-bearing: `NarrateHandler` is the one
  /// LLM call site not wrapped in `turnGate.attempt`, and it catches around the
  /// call — so a throw there would be swallowed, costing the round its narration
  /// with no `.turnSkipped` and no breaker increment. This test pins only the
  /// `primaryField == nil` half; the "no un-gated, un-catching call site" half
  /// is unpinnable here and lives in `.claude/rules/engine.md`.
  @Test func narrateIsStructurallyExcluded() async throws {
    let mock = MockLLMService(responses: [
      #"{"commentary": ""}"#,
      #"{"commentary": ""}"#,
      #"{"commentary": ""}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Narrator",
      phaseType: .narrate,
      schema: OutputSchema(fields: [
        OutputSchema.Field(name: "commentary", kind: .string)
      ]),
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.fields["commentary"] == "")
    #expect(mock.generateCallCount == 3, "still retries on the empty value, but never throws")
  }
}
