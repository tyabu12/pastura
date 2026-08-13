import Testing

@testable import Pastura

/// `knownTurnMarkers` coverage (#1422). Sibling extension rather than a new
/// suite, per `.claude/rules/testing.md` § "Splitting a Suite Across Files" —
/// `LlamaCppServiceTests` is `.serialized` and near the 400-line cap.
extension LlamaCppServiceTests {
  private func gemmaShapedService() -> LlamaCppService {
    LlamaCppService(
      modelPath: "/nonexistent.gguf",
      stopSequence: "<|im_end|>",
      turnMarkers: ChatTurnMarkers(start: "<|turn>", end: "<turn|>"),
      modelIdentifier: "test-gemma",
      systemPromptSuffix: nil
    )
  }

  /// A non-ChatML model surfaces **both** its own pair and the ChatML baseline
  /// — the union rule (#1422 D3). Order is load-bearing only in that the
  /// model's own pair must be present at all.
  @Test func knownTurnMarkers_unionsModelPairWithChatMLBaseline() {
    let markers = gemmaShapedService().knownTurnMarkers
    #expect(markers.contains(ChatTurnMarkers(start: "<|turn>", end: "<turn|>")))
    #expect(markers.contains(.chatML))
    #expect(markers.count == 2)
  }

  /// A ChatML model must not grow a duplicate entry — consumers iterate this
  /// set per parse, and a doubled pair would do the same work twice.
  @Test func knownTurnMarkers_dedupesWhenModelIsChatML() {
    let service = makeTestService()
    #expect(service.knownTurnMarkers == [.chatML])
  }

  /// **The D2 regression test.** `knownTurnMarkers` is declared in the
  /// `LLMService` protocol *body*, so it dispatches dynamically; moving the
  /// declaration into an extension would statically dispatch through
  /// `any LLMService` and silently return the default `[.chatML]` at the
  /// `LLMCaller` call site — which is exactly how the caller holds its backend.
  ///
  /// Revert the declaration to extension-only and this test fails while the
  /// two above still pass, because they hold a concrete `LlamaCppService`.
  @Test func knownTurnMarkers_dispatchesDynamicallyThroughExistential() {
    let service: any LLMService = gemmaShapedService()
    #expect(service.knownTurnMarkers.contains(ChatTurnMarkers(start: "<|turn>", end: "<turn|>")))
    #expect(service.knownTurnMarkers != [.chatML])
  }

  /// Backends that cannot name their model keep the pre-#1422 ChatML-only
  /// behaviour through the protocol-extension default.
  @Test func knownTurnMarkers_defaultsToChatMLForBackendsWithoutADescriptor() {
    let mock: any LLMService = MockLLMService(responses: [])
    #expect(mock.knownTurnMarkers == [.chatML])
  }
}
