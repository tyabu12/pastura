import Foundation
import Testing

@testable import Pastura

/// Pins the per-model turn markers in `ModelRegistry`, and the one place where
/// they **deliberately disagree** with the older `stopSequence` field (#1422).
///
/// Own suite, not a `ModelRegistryTests` extension: the subject is a
/// cross-field invariant, findable by name. Safe alongside that suite since
/// `ModelRegistry` is immutable static data
/// (`.claude/rules/testing.md` § "Splitting a Suite Across Files").
@Suite(.timeLimit(.minutes(1)))
struct ModelRegistryTurnMarkerDivergenceTests {
  /// **Regression.** Pre-#1422, every marker-keyed mechanism used ChatML
  /// unconditionally, matching nothing for the default model. Reverting
  /// Gemma's descriptor to `.chatML` reddens here. Values from the GGUF
  /// header of `gemma4E2B`'s pinned file: `<|turn>` id 105 / `<turn|>` id 106.
  @Test func gemma_carriesItsOwnMarkers_notChatML() {
    let markers = ModelRegistry.gemma4E2B.turnMarkers
    #expect(markers.start == "<|turn>")
    #expect(markers.end == "<turn|>")
    #expect(markers != .chatML)
  }

  /// **Control.** Qwen 3 genuinely is ChatML — the "Qwen unchanged" half of
  /// #1422's acceptance criteria at the descriptor level.
  @Test func qwen_isChatML() {
    #expect(ModelRegistry.qwen34B.turnMarkers == .chatML)
  }

  /// **Deliberate divergence, deferred to #1451.** For Gemma, `stopSequence`
  /// is a ChatML string absent from the vocabulary, so it's inert; repointing
  /// it would activate a behaviour on an assumption, and a false positive
  /// there truncates a real payload — worse than today's no-op.
  ///
  /// A failure here is **not** automatically a bug: read #1451 before
  /// updating this expectation.
  @Test func gemma_stopSequenceDeliberatelyDisagreesWithTurnMarkers() {
    let descriptor = ModelRegistry.gemma4E2B
    #expect(descriptor.stopSequence != descriptor.turnMarkers.end)
    #expect(descriptor.stopSequence == ChatTurnMarkers.chatML.end)
  }

  /// A descriptor could pass empty strings even though `turnMarkers` has no
  /// default. Failure mode is **silence, not over-matching** — an empty pair
  /// goes inert, quietly reintroducing #1422's bug — so it must be asserted
  /// here, not left to the truncator (see
  /// `JSONResponseParserTests.emptyMarkerStrings_areIgnored`).
  @Test func everyCatalogEntryHasNonEmptyMarkers() {
    for descriptor in ModelRegistry.catalog {
      #expect(!descriptor.turnMarkers.start.isEmpty, "\(descriptor.id) start")
      #expect(!descriptor.turnMarkers.end.isEmpty, "\(descriptor.id) end")
    }
  }
}
