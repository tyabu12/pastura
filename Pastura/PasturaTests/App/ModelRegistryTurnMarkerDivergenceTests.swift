import Foundation
import Testing

@testable import Pastura

/// Pins the per-model turn markers in `ModelRegistry`, and the one place where
/// they **deliberately disagree** with the older `stopSequence` field — a
/// disagreement that is now the decided rule (#1451), not a carve-out
/// (#1422).
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

  /// The QAT re-export carries the same pair, but read from **its own** GGUF
  /// header rather than copied across (`docs/models/onboarding.md`
  /// § "Stage 0 — Harness profile": a marker is a property of the export). The
  /// two agreeing is the measurement's result, not its premise — the same read
  /// found `eos_token_id` differing between the files.
  @Test func gemmaQAT_carriesTheSameMeasuredMarkers() {
    let markers = ModelRegistry.gemma4E2BQAT.turnMarkers
    #expect(markers.start == "<|turn>")
    #expect(markers.end == "<turn|>")
    #expect(markers != .chatML)
  }

  /// **Control.** Qwen 3 genuinely is ChatML — the "Qwen unchanged" half of
  /// #1422's acceptance criteria at the descriptor level.
  @Test func qwen_isChatML() {
    #expect(ModelRegistry.qwen34B.turnMarkers == .chatML)
  }

  /// **Decided in #1451.** `stopSequence` is the generation-side
  /// ChatML-hallucination guard, shared across every model by design — not a
  /// per-model marker. A model's own end marker is CONTROL + EOG, so on a
  /// correct export it never decodes into text (`decodePiece(special: false)`
  /// renders it `""`, and `llama_vocab_is_eog` stops the turn first anyway),
  /// meaning a per-model literal here could never truncate — repointing
  /// `stopSequence` to `turnMarkers.end` was considered and rejected as zero
  /// upside, new risk (canonical rationale: `LlamaCppService.stopSequence`).
  ///
  /// So under the #1451 rule, EVERY catalog entry — Gemma family included —
  /// must carry the ChatML string, and a NEW non-ChatML model is *expected* to
  /// diverge from its own `turnMarkers.end` and still pass here, as long as it
  /// carries the ChatML guard. The pre-#1451 id allowlist (`Set(divergent
  /// ids) == [the two Gemma ids]`) was dropped knowingly: divergence is now
  /// the rule, so an allowlist would redden on every legitimate non-ChatML
  /// onboarding; the price is that a newly-divergent entry no longer has to
  /// be named here. Do not re-add it.
  ///
  /// Any failure here — including the "consistency fix" of repointing Gemma
  /// to `<turn|>`, which reddens the first loop with that id in the message —
  /// means read #1451 before "fixing": the repoint is the deliberately
  /// rejected case. The second loop is deliberately thin: given the first, it
  /// can only fire for a future non-ChatML pair whose `end` happens to equal
  /// `<|im_end|>`; it stays as the intent pin in the other direction (a
  /// genuinely ChatML descriptor such as Qwen agrees by construction and is
  /// excluded). Both `stopSequence` comments in `ModelRegistry`
  /// promise that `grep -rn '#1451'` enumerates every decision site; this
  /// doc comment is one of them. (Run that command rather than trusting a
  /// quoted phrase here: the promise is hard-wrapped across comment lines, so
  /// it does not grep as one string.)
  ///
  /// This sweep reaches only descriptors still **in** `catalog`. If an entry
  /// is later dropped from `catalog` entirely (rather than hidden via
  /// `ModelManager.visibleCatalog`, `ModelRegistry` § "ADD-and-keep"), that
  /// reddens `catalog_hasExpectedModels` — which pins all three ids — before
  /// this sweep's coverage silently narrows.
  @Test func everyCatalogEntryCarriesTheChatMLGuard_notItsOwnEndMarker() {
    for descriptor in ModelRegistry.catalog {
      #expect(descriptor.stopSequence == ChatTurnMarkers.chatML.end, "\(descriptor.id)")
    }
    for descriptor in ModelRegistry.catalog where descriptor.turnMarkers != .chatML {
      #expect(descriptor.stopSequence != descriptor.turnMarkers.end, "\(descriptor.id)")
    }
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
