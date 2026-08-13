import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ChatTurnMarkersTests {
  /// `.chatML` is the baseline every consumer unions into its effective set,
  /// so backends with no descriptor to consult (Ollama, `MockLLMService`,
  /// FoundationModels) keep their pre-#1422 behaviour. Pinning the literals
  /// here means a reword of either one shows up as a deliberate edit rather
  /// than as a silently-widened or silently-narrowed match set.
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

  /// Equality must discriminate on **both** fields — the effective-set union
  /// in `LLMService.knownTurnMarkers` dedupes by `Hashable`, so a pair that
  /// compared equal on `start` alone would silently drop a distinct `end`.
  @Test func hashable_discriminatesOnEachField() {
    let base = ChatTurnMarkers(start: "<a>", end: "</a>")
    #expect(base != ChatTurnMarkers(start: "<b>", end: "</a>"))
    #expect(base != ChatTurnMarkers(start: "<a>", end: "</b>"))
  }
}
