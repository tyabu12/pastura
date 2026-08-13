import Foundation
import Testing

@testable import Pastura

/// A backend reporting a non-ChatML marker pair, so `LLMCaller` can be driven
/// down the per-model path (#1422). Wrapper, not a `MockLLMService` subclass:
/// `LLMCaller` must read `knownTurnMarkers` through the existential.
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
/// **Control** (passes both before and after — gives a Regression test its
/// contrast).
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

  /// **Regression.** `LLMCaller` must read the marker set from the live backend —
  /// the integration half of the D2 dynamic-dispatch pin: a statically-dispatched
  /// declaration would silently fall back to ChatML here.
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

  /// **Control.** Same response, ChatML-only backend: takes the fabricated
  /// continuation — the bug #1422 fixes, demonstrated rather than asserted so
  /// the test above can't pass for an unrelated reason.
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

  /// **Regression.** The leakage diagnostic is model-aware: a Gemma turn-start
  /// marker now raises `.warning`, where pre-#1422 it raised nothing.
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

  /// **Control.** Same raw text through a ChatML-only backend raises no warning —
  /// the silence that made this diagnostic useless for the default shipped
  /// model. Asserts the absence of **any** `.warning`, not of the substring
  /// `<|turn>`, so it isn't coupled to the message wording (which this PR
  /// changed).
  ///
  /// Not vacuous: `leakageDiagnosticWarnsOnBackendStartMarker` above drives the
  /// same raw text to a `.warning`, so only the marker set differs here.
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

  /// **Regression.** A ChatML backend keeps the pre-#1422 severity split and
  /// marker detection — not the wording, which this PR reworded (see
  /// `logChatTemplateLeakage`); the substring below appears only post-#1422.
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
