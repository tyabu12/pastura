import Foundation
import Testing

@testable import Pastura

/// A backend that behaves exactly like ``MockLLMService`` but reports a
/// non-ChatML marker pair, so `LLMCaller` can be driven down the per-model
/// path (#1422).
///
/// Deliberately a wrapper rather than a `MockLLMService` subclass: the point
/// under test is that `LLMCaller` reads `knownTurnMarkers` **through the
/// existential**, so the stub must be a distinct conforming type.
nonisolated final class GemmaMarkerLLMService: LLMService, @unchecked Sendable {
  private let inner: MockLLMService

  init(responses: [String]) {
    inner = MockLLMService(responses: responses)
  }

  var knownTurnMarkers: [ChatTurnMarkers] {
    [ChatTurnMarkers(start: "<|turn>", end: "<turn|>"), .chatML]
  }

  func loadModel() async throws { try await inner.loadModel() }
  func unloadModel() async throws { try await inner.unloadModel() }
  var isModelLoaded: Bool { inner.isModelLoaded }
  var modelIdentifier: String { "gemma-stub" }
  var backendIdentifier: String { "mock" }

  func generate(
    system: String, user: String, schema: OutputSchema?, antiRepetitionSeeds: [String]
  ) async throws -> String {
    try await inner.generate(
      system: system, user: user, schema: schema, antiRepetitionSeeds: antiRepetitionSeeds)
  }
}

/// End-to-end threading of the per-model markers through `LLMCaller` (#1422).
///
/// Each test is labelled **Regression** (fails if the fix is reverted) or
/// **Control** (passes both before and after — it exists to give a Regression
/// test its contrast). Three of the five are regression tests; do not read the
/// file's length as five independent guards.
extension LLMCallerTests {
  /// The raw shape that actually loses the payload: a **fenced** fabricated
  /// continuation, which `extractFromCodeBlock` lifts out ahead of the
  /// balanced-brace scan.
  private static let gemmaHallucination = """
    {"statement": "本物", "inner_thought": "考え中"}<turn|>
    <|turn>user
    もう一度
    <turn|>
    <|turn>model
    ```json
    {"statement": "偽物", "inner_thought": "別"}
    ```
    """

  /// **Regression.** `LLMCaller` must read the marker set from the live backend. This is the
  /// integration half of the D2 dynamic-dispatch pin: the caller holds
  /// `any LLMService`, so a statically-dispatched declaration would silently
  /// fall back to ChatML here.
  @Test func usesBackendTurnMarkersWhenParsing() async throws {
    let gemma = GemmaMarkerLLMService(responses: [Self.gemmaHallucination])
    try await gemma.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: gemma, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      suspendController: SuspendController(),
      emitter: collector.emit)

    #expect(result.statement == "本物")
  }

  /// **Control.** Negative control on the identical response: a ChatML-only backend takes
  /// the fabricated continuation. This is the bug #1422 fixes, so it must be
  /// demonstrated rather than asserted — without it, the test above could pass
  /// for reasons unrelated to the marker set.
  @Test func chatMLOnlyBackendStillTakesTheFabricatedContinuation() async throws {
    let mock = MockLLMService(responses: [Self.gemmaHallucination])
    try await mock.loadModel()

    let collector = EventCollector()
    let result = try await caller.call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      suspendController: SuspendController(),
      emitter: collector.emit)

    #expect(result.statement == "偽物")
  }

  /// **Regression.** The leakage diagnostic is model-aware: a Gemma turn-start marker now
  /// raises the `.warning`, where before #1422 it raised nothing at all.
  @Test func leakageDiagnosticWarnsOnBackendStartMarker() async throws {
    let gemma = GemmaMarkerLLMService(responses: [Self.gemmaHallucination])
    try await gemma.loadModel()
    let spy = SpyEngineLogger()

    let collector = EventCollector()
    _ = try await LLMCaller(logger: spy).call(
      llm: gemma, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      suspendController: SuspendController(),
      emitter: collector.emit)

    let warnings = spy.entries.filter { $0.level == .warning }
    #expect(warnings.contains { $0.message.contains("<|turn>") })
    #expect(warnings.allSatisfy { $0.privacy == .public })
  }

  /// **Control.** The same raw text through a ChatML-only backend raises **no**
  /// warning — the silence that made this diagnostic useless for the default
  /// shipped model. Pins the delta rather than merely the fixed behaviour.
  ///
  /// Asserts the absence of **any** `.warning`, not the absence of the string
  /// `<|turn>`: a substring probe passes on pre-#1422 code for the trivial
  /// reason that no line is emitted at all, and it also silently couples the
  /// control to the message wording. Not vacuous — `leakageDiagnosticWarnsOn
  /// BackendStartMarker` above drives the same raw text to a `.warning`, so
  /// warnings are reachable on this input and only the marker set differs.
  @Test func leakageDiagnosticIsSilentForNonMatchingMarkers() async throws {
    let mock = MockLLMService(responses: [Self.gemmaHallucination])
    try await mock.loadModel()
    let spy = SpyEngineLogger()

    let collector = EventCollector()
    _ = try await LLMCaller(logger: spy).call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      suspendController: SuspendController(),
      emitter: collector.emit)

    #expect(!spy.entries.contains { $0.level == .warning })
  }

  /// **Regression.** A ChatML backend keeps the pre-#1422 diagnostic behaviour verbatim.
  @Test func leakageDiagnosticStillWarnsOnChatMLStartMarker() async throws {
    let raw = """
      {"statement": "hello"}<|im_end|>
      <|im_start|>user
      again
      """
    let mock = MockLLMService(responses: [raw])
    try await mock.loadModel()
    let spy = SpyEngineLogger()

    let collector = EventCollector()
    _ = try await LLMCaller(logger: spy).call(
      llm: mock, system: "sys", user: "usr", agentName: "Alice",
      phaseType: .speakAll,
      suspendController: SuspendController(),
      emitter: collector.emit)

    #expect(
      spy.entries.contains {
        $0.level == .warning && $0.message.contains("<|im_start|>")
      })
  }
}
