import Foundation
import Testing

@testable import Pastura

/// Pins the per-model turn markers in `ModelRegistry`, and the one place where
/// they **deliberately disagree** with the older `stopSequence` field (#1422).
///
/// Its own suite rather than an extension of `ModelRegistryTests`: the subject
/// is a cross-field invariant that a reader looking for "why do these two
/// disagree?" should be able to find by name. Safe to run alongside that suite
/// — `ModelRegistry` is immutable static data, so there is no shared mutable
/// state to race on (`.claude/rules/testing.md` § "Splitting a Suite Across
/// Files").
@Suite(.timeLimit(.minutes(1)))
struct ModelRegistryTurnMarkerDivergenceTests {
  /// The bug #1422 fixes, stated as an assertion: before the fix, every
  /// mechanism keyed on turn markers used the ChatML pair unconditionally, so
  /// for the **default shipped model** it matched nothing. Reverting Gemma's
  /// descriptor to `.chatML` reddens here.
  ///
  /// Values are from the GGUF header of the exact file `gemma4E2B` pins:
  /// `<|turn>` id 105 / `<turn|>` id 106, both CONTROL, `eos = 106`.
  @Test func gemma_carriesItsOwnMarkers_notChatML() {
    let markers = ModelRegistry.gemma4E2B.turnMarkers
    #expect(markers.start == "<|turn>")
    #expect(markers.end == "<turn|>")
    #expect(markers != .chatML)
  }

  /// Qwen 3 genuinely is a ChatML model, so the pre-#1422 hardcoded literal
  /// was correct for it. This is the "Qwen behaviour unchanged" half of the
  /// issue's acceptance criteria at the descriptor level.
  @Test func qwen_isChatML() {
    #expect(ModelRegistry.qwen34B.turnMarkers == .chatML)
  }

  /// **Deliberate divergence, deferred to #1451.** `stopSequence` is the
  /// generation-side early-stop sentinel; for Gemma it is a ChatML string
  /// absent from the model's 262,144-token vocabulary, so that path is inert.
  /// Repointing it to `turnMarkers.end` would newly *activate* a behaviour on
  /// an assumption rather than a demonstration — and a false positive there
  /// truncates a real payload mid-generation, which is strictly worse than
  /// today's no-op.
  ///
  /// A failure here is **not** automatically a bug: it means someone made the
  /// two agree. Read #1451 and confirm the evidence exists before updating
  /// this expectation.
  @Test func gemma_stopSequenceDeliberatelyDisagreesWithTurnMarkers() {
    let descriptor = ModelRegistry.gemma4E2B
    #expect(descriptor.stopSequence != descriptor.turnMarkers.end)
    #expect(descriptor.stopSequence == ChatTurnMarkers.chatML.end)
  }

  /// Every catalog entry must state a usable pair. `turnMarkers` has no default
  /// value precisely so this cannot be reached by omission — but a descriptor
  /// could still pass empty strings, which would make the truncation predicate
  /// match at every index.
  @Test func everyCatalogEntryHasNonEmptyMarkers() {
    for descriptor in ModelRegistry.catalog {
      #expect(!descriptor.turnMarkers.start.isEmpty, "\(descriptor.id) start")
      #expect(!descriptor.turnMarkers.end.isEmpty, "\(descriptor.id) end")
    }
  }
}
