import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ChatTurnMarkersTests {
  /// `.chatML` is the baseline every consumer unions into its effective set,
  /// so backends with no descriptor (Ollama, `MockLLMService`,
  /// FoundationModels) keep pre-#1422 behaviour.
  @Test func chatML_carriesTheChatMLPair() {
    #expect(ChatTurnMarkers.chatML.start == "<|im_start|>")
    #expect(ChatTurnMarkers.chatML.end == "<|im_end|>")
  }

  @Test func init_storesBothMarkers() {
    let markers = ChatTurnMarkers(start: "<|turn>", end: "<turn|>")
    #expect(markers.start == "<|turn>")
    #expect(markers.end == "<turn|>")
  }

  // MARK: - Hashable

  @Test func hashable_equalPairsHashEqual() {
    let lhs = ChatTurnMarkers(start: "<a>", end: "</a>")
    let rhs = ChatTurnMarkers(start: "<a>", end: "</a>")
    #expect(lhs == rhs)
    #expect(lhs.hashValue == rhs.hashValue)
  }

  /// Equality must discriminate on **both** fields: `LlamaCppService.knownTurnMarkers`
  /// decides its union with a `turnMarkers == .chatML` ternary, so an `==`
  /// ignoring `end` would collapse a descriptor sharing ChatML's `start` into
  /// the bare `[.chatML]` arm, silently dropping its `end` from the set the
  /// truncator iterates.
  @Test func hashable_discriminatesOnEachField() {
    let base = ChatTurnMarkers(start: "<a>", end: "</a>")
    #expect(base != ChatTurnMarkers(start: "<b>", end: "</a>"))
    #expect(base != ChatTurnMarkers(start: "<a>", end: "</b>"))
  }
}
