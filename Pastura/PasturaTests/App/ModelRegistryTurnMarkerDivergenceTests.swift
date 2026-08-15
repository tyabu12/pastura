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

  /// **Deliberate divergence, deferred to #1451.** For a Gemma descriptor,
  /// `stopSequence` is a ChatML string absent from the vocabulary, so it's
  /// inert; repointing it would activate a behaviour on an assumption, and a
  /// false positive there truncates a real payload — worse than today's no-op.
  ///
  /// Asserted over the whole catalog rather than on `gemma4E2B` alone. The
  /// inertness is a property of each **export's** vocabulary, so every divergent
  /// descriptor owes its own header measurement — and `ModelRegistry`'s
  /// `stopSequence` comment promises "#1451, which must change every site
  /// (`grep -rn '#1451'`)", which a per-descriptor test cannot keep true. The id
  /// set is what makes a newly-divergent entry redden instead of landing
  /// unmarked; it is order-independent, since order is not the invariant.
  ///
  /// A failure here is **not** automatically a bug: read #1451 first. Adding a
  /// Gemma-family descriptor legitimately extends the set; anything else
  /// diverging means the pair drifted by accident.
  @Test func everyDivergentDescriptorIsTheDeliberateChatMLCase() {
    let divergent = ModelRegistry.catalog.filter { $0.stopSequence != $0.turnMarkers.end }
    #expect(Set(divergent.map(\.id)) == ["gemma-4-e2b-q4-k-m", "gemma-4-e2b-qat-q4-k-xl"])
    for descriptor in divergent {
      #expect(descriptor.stopSequence == ChatTurnMarkers.chatML.end, "\(descriptor.id)")
    }
  }

  /// Static-referenced companion to the catalog sweep above, which only reaches
  /// descriptors still **in** `catalog`. The planned follow-up hides a legacy
  /// entry and may drop `gemma4E2B` from it while the static stays live for users
  /// who already downloaded that build — at which point the sweep would assert
  /// nothing about it, silently. Keep both arms.
  @Test func bothGemmaStaticsCarryTheDivergence() {
    for descriptor in [ModelRegistry.gemma4E2B, ModelRegistry.gemma4E2BQAT] {
      #expect(descriptor.stopSequence != descriptor.turnMarkers.end, "\(descriptor.id)")
      #expect(descriptor.stopSequence == ChatTurnMarkers.chatML.end, "\(descriptor.id)")
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
