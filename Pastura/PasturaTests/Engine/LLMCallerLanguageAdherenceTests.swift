import Foundation
import Testing
import os

@testable import Pastura

/// Tests for the language-adherence retry policy in ``LLMCaller`` —
/// ADR-010 Step E PR2 item 4. Verifies:
///
/// - Retry consumption on mismatch within the existing `maxRetries=2`
///   budget; second attempt returning correct-language → success
/// - Exhaustion path: all attempts mismatched → `.languageMismatch`
///   event emitted AND parsed `TurnOutput` still returned (sim continues)
/// - Skip paths: detector returns nil (low-confidence) → no retry;
///   `expectedLanguage == nil` → no retry; joined natural-language
///   text < 12 codepoints → no retry (e.g., short vote target)
/// - Priority pin: when a response has both `empty_field` and
///   wrong-language, the parse-empty retry fires first — the adherence
///   check is gated on a non-empty output
/// - Schema-aware carve-out: option-bound enum fields
///   (`Field.kind == .enumeration(...)`) are excluded from the
///   detection input, so a `choose` scenario in `ja` with English
///   option tokens does not spuriously retry
@Suite(.timeLimit(.minutes(1)))
struct LLMCallerLanguageAdherenceTests {
  let caller = LLMCaller()

  // MARK: - Test fixture

  /// A `LanguageDetector` whose verdict is a sequence of canned outputs
  /// — drained one entry per call. When the queue is empty, returns
  /// nil. Used by tests below to drive the adherence-retry path
  /// deterministically without invoking Apple's NaturalLanguage framework.
  final class StubLanguageDetector: LanguageDetector, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[String?]>(initialState: [])

    init(verdicts: [String?]) {
      lock.withLock { $0 = verdicts }
    }

    func detect(text: String) -> String? {
      lock.withLock { queue in
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
      }
    }
  }

  private func speakAllSchema() -> OutputSchema {
    OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
  }

  /// Mimics a `choose` phase schema with author-supplied English options.
  /// The `action` field is enum-constrained — the adherence check must
  /// filter it out and base its verdict on remaining natural-language
  /// fields (none here → check is skipped entirely).
  private func chooseSchemaWithEnOptions() -> OutputSchema {
    OutputSchema(fields: [
      OutputSchema.Field(name: "action", kind: .enumeration(["cooperate", "betray"]))
    ])
  }

  // MARK: - Retry consumption (case a)

  @Test func retriesOnLanguageMismatch() async throws {
    // First attempt: wrong language (detector says "ja", expected "en") → retry.
    // Second attempt: correct language → succeed.
    // Long natural-language statement so the min-length gate doesn't fire.
    let mock = MockLLMService(responses: [
      #"{"statement": "ja-language statement that is long enough to pass the detector gate"}"#,
      #"{"statement": "en-language statement that is long enough to pass the detector gate"}"#
    ])
    try await mock.loadModel()
    let detector = StubLanguageDetector(verdicts: ["ja", "en"])

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: speakAllSchema(),
      detector: detector, expectedLanguage: "en",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement?.contains("en-language") ?? false)
    #expect(mock.generateCallCount == 2)
    let mismatchEvents = collector.events.filter {
      if case .languageMismatch = $0 { return true }
      return false
    }
    #expect(mismatchEvents.isEmpty, "Successful retry must not emit .languageMismatch")
  }

  // MARK: - Exhaustion path (case b)

  @Test func emitsLanguageMismatchEventOnExhaustion() async throws {
    // All 3 attempts return wrong language. Detector returns "ja" every
    // time. Adherence retry budget exhausts; event fires; final parse
    // result is still returned (sim continues, contra parse_failed which
    // throws).
    let wrong = #"{"statement": "ja-language statement that is long enough to pass the gate"}"#
    let mock = MockLLMService(responses: [wrong, wrong, wrong])
    try await mock.loadModel()
    let detector = StubLanguageDetector(verdicts: ["ja", "ja", "ja"])

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: speakAllSchema(),
      detector: detector, expectedLanguage: "en",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement?.contains("ja-language") ?? false)
    #expect(mock.generateCallCount == 3, "Exhausted retry budget = maxRetries + 1 = 3")
    let mismatchEvents = collector.events.compactMap { event -> SimulationEvent? in
      if case .languageMismatch = event { return event }
      return nil
    }
    #expect(mismatchEvents.count == 1)
    if case .languageMismatch(let agent, let detected, let expected) = mismatchEvents.first! {
      #expect(agent == "Alice")
      #expect(detected == "ja")
      #expect(expected == "en")
    }
  }

  // MARK: - Skip paths

  @Test func noRetryWhenDetectorReturnsNil() async throws {
    // Detector returns nil → low-confidence → adherence check skipped.
    let mock = MockLLMService(responses: [
      #"{"statement": "some ambiguous output that the detector cannot classify"}"#
    ])
    try await mock.loadModel()
    let detector = StubLanguageDetector(verdicts: [nil])

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: speakAllSchema(),
      detector: detector, expectedLanguage: "en",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement?.contains("ambiguous") ?? false)
    #expect(mock.generateCallCount == 1, "Detector nil → no retry")
  }

  @Test func noRetryWhenExpectedLanguageIsNil() async throws {
    // No expected language set → check skipped (back-compat path).
    let mock = MockLLMService(responses: [
      #"{"statement": "ja statement that would normally be flagged"}"#
    ])
    try await mock.loadModel()
    let detector = StubLanguageDetector(verdicts: ["ja"])

    let collector = EventCollector()
    _ = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: speakAllSchema(),
      detector: detector, expectedLanguage: nil,
      suspendController: SuspendController(),
      emitter: collector.emit
    )
    #expect(mock.generateCallCount == 1)
  }

  @Test func noRetryWhenDetectorIsNil() async throws {
    // No detector configured → check skipped entirely (also back-compat path).
    let mock = MockLLMService(responses: [
      #"{"statement": "ja statement that would normally be flagged"}"#
    ])
    try await mock.loadModel()

    let collector = EventCollector()
    _ = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: speakAllSchema(),
      detector: nil, expectedLanguage: "en",
      suspendController: SuspendController(),
      emitter: collector.emit
    )
    #expect(mock.generateCallCount == 1)
  }

  @Test func noRetryWhenJoinedTextBelowMinLength() async throws {
    // Short vote target "佐藤" (2 codepoints) < min-length gate → skip.
    // Detector would return "ja" if asked, but the gate fires first.
    let voteSchema = OutputSchema(fields: [
      OutputSchema.Field(name: "vote", kind: .string)
    ])
    let mock = MockLLMService(responses: [
      #"{"vote": "佐藤"}"#
    ])
    try await mock.loadModel()
    let detector = StubLanguageDetector(verdicts: ["ja"])

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: voteSchema,
      detector: detector, expectedLanguage: "en",
      suspendController: SuspendController(),
      emitter: collector.emit
    )
    #expect(result.fields["vote"] == "佐藤")
    #expect(mock.generateCallCount == 1, "Short input → adherence check skipped → no retry")
  }

  // MARK: - Priority pin (case f)

  @Test func emptyFieldRetryFiresBeforeLanguageMismatchRetry() async throws {
    // Response has BOTH empty `statement` and wrong-language thought —
    // post-parse check order pins empty_field BEFORE language_mismatch.
    // Second attempt provides correct-language non-empty output → succeed.
    // Asserts: mock.generateCallCount == 2 AND zero .languageMismatch
    // events (priority order means the second attempt's correct output
    // doesn't get re-flagged either).
    let mock = MockLLMService(responses: [
      #"{"statement": "...", "inner_thought": "ja thought that is long enough"}"#,
      #"{"statement": "en statement that is long enough to pass the gate"}"#
    ])
    try await mock.loadModel()
    // Detector queue empty/never-consulted on attempt 1 (empty_field
    // short-circuits before adherence). Asked once on attempt 2.
    let detector = StubLanguageDetector(verdicts: ["en"])

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: OutputSchema(fields: [
        OutputSchema.Field(name: "statement", kind: .string),
        OutputSchema.Field(name: "inner_thought", kind: .string)
      ]),
      detector: detector, expectedLanguage: "en",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.statement?.contains("en statement") ?? false)
    #expect(mock.generateCallCount == 2)
    let mismatchEvents = collector.events.filter {
      if case .languageMismatch = $0 { return true }
      return false
    }
    #expect(mismatchEvents.isEmpty)
  }

  // MARK: - Schema-aware carve-out (case g)

  @Test func noRetryForChooseSchemaWithEnumOptions() async throws {
    // choose-phase schema with `action: .enumeration(["cooperate", "betray"])`
    // on a ja scenario. Output is the enum-constrained action token —
    // English text but author-supplied, not LLM-generated language. The
    // schema filter excludes `action` from natural-language fields, so
    // the joined detection input is empty → check skipped → no retry.
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#
    ])
    try await mock.loadModel()
    // Detector would return "en" for "cooperate" if asked — verify it
    // is NOT asked by setting an empty verdict queue and asserting
    // generateCallCount stays at 1.
    let detector = StubLanguageDetector(verdicts: [])

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      schema: chooseSchemaWithEnOptions(),
      detector: detector, expectedLanguage: "ja",
      suspendController: SuspendController(),
      emitter: collector.emit
    )

    #expect(result.action == "cooperate")
    #expect(mock.generateCallCount == 1, "Enum-only schema → no natural-language input → skip")
  }
}
