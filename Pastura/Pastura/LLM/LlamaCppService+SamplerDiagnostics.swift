import Foundation
import LlamaSwift
import os

// MARK: - Sampler diagnostics

/// Per-token diagnostic context threaded through the sampling path so the
/// always-on sampler telemetry (`samplerCrashCaught` /
/// `samplerMaskedSelection`) can attribute events to the calling loop and
/// the generation position without widening every signature past the
/// SwiftLint parameter budget.
nonisolated struct SamplerDiagContext {
  /// `non-stream` / `stream` tag identifying the calling generation loop.
  let mode: String
  /// 0-based count of content tokens generated before this sampling step.
  /// `position == 0` masked-selection events surface as empty output
  /// (#751 sub-class 2).
  let position: Int
}

extension LlamaCppService {
  /// #751 sub-class 2 diagnostic: fires when the sampler chain selected a
  /// grammar-masked (-inf) token. Two observed sub-modes, both
  /// deterministic (RNG-independent — retries of the same prompt
  /// mis-select identically), both from llama.cpp's dist sampler
  /// (`src/llama-sampler.cpp:1042-1103` at b10327) whose `assert(found)` is compiled
  /// out of the release xcframework:
  ///
  /// - (a) grammar rejected EVERY truncated candidate → all-NaN softmax →
  ///   the `sum_run >= sum_tgt` scan never fires → falls through to the
  ///   LAST candidate (`finiteCandidates=0`);
  /// - (b) grammar masked the TOP-ranked candidate while finite candidates
  ///   remain (`finiteCandidates>0`): top_k left `sorted=true`, so dist
  ///   takes `max_l = data[0].logit = -inf` without rescanning and the
  ///   softmax degenerates (exp(+inf)/NaN) → garbage selection despite
  ///   valid tokens in the set.
  ///
  /// Detection is the selected token's -inf logit (O(1), checked by the
  /// caller). `position=0` events surface as empty output (EOG → 0-token
  /// break; non-EOG → grammar-accept throw → catch-as-EOS with empty
  /// text). Logs the token ID only — never the decoded piece (CLAUDE.md
  /// "Logger privacy"). Occurrence-rate telemetry: fires once per event.
  func emitMaskedSelectionDiagnostic(
    token: Int32,
    curP: llama_token_data_array,
    vocab: OpaquePointer?,
    diag: SamplerDiagContext
  ) {
    guard let data = curP.data else { return }
    var finiteCandidates = 0
    for i in 0..<Int(curP.size) where data[i].logit > -Float.infinity {
      finiteCandidates += 1
    }
    let isEOG = llama_vocab_is_eog(vocab, token)
    Self.samplerCatchDiagLogger.error(
      """
      samplerMaskedSelection tokenId=\(token, privacy: .public) \
      isEOG=\(isEOG, privacy: .public) \
      position=\(diag.position, privacy: .public) \
      finiteCandidates=\(finiteCandidates, privacy: .public) \
      candidates=\(curP.size, privacy: .public) \
      mode=\(diag.mode, privacy: .public) \
      model=\(self.modelIdentifier, privacy: .public)
      """)
    // Mirror to stderr for the macOS harness (ADR-013): CLI os.Logger
    // output is not reliably queryable via `log show`, and the harness
    // captures stderr to `<out>.stderr.log`. Rare path (once per
    // masked-selection event); invisible and harmless on iOS. Same
    // privacy discipline — token ID only, never the decoded piece.
    fputs(
      "samplerMaskedSelection tokenId=\(token) isEOG=\(isEOG) "
        + "position=\(diag.position) finiteCandidates=\(finiteCandidates) "
        + "candidates=\(curP.size) mode=\(diag.mode) model=\(modelIdentifier)\n",
      stderr)
  }

  /// #751: fires when pass 1 (grammar-free chain) picked a token the grammar
  /// rejects, so ``grammarConstrainedSample`` had to resample grammar-first.
  ///
  /// Emitted only at `position == 0` — a nonzero position-0 resample rate is
  /// the empty-output fragility signal for the model-onboarding pipeline (a
  /// weak JSON prior that would, pre-fix, have produced "Model generated no
  /// output tokens"). Post-fix these are *rescued*, not failures, so this is
  /// a health metric, not an error. Off the hot path (only when a resample
  /// is actually needed) and position-gated to stay low-volume. Token ID
  /// only — never the decoded piece (CLAUDE.md "Logger privacy").
  func emitGrammarResampleDiagnostic(
    rejectedToken: Int32, vocab: OpaquePointer?, diag: SamplerDiagContext
  ) {
    guard diag.position == 0 else { return }
    let isEOG = llama_vocab_is_eog(vocab, rejectedToken)
    Self.samplerCatchDiagLogger.error(
      """
      samplerGrammarResample rejectedTokenId=\(rejectedToken, privacy: .public) \
      isEOG=\(isEOG, privacy: .public) \
      position=\(diag.position, privacy: .public) \
      mode=\(diag.mode, privacy: .public) \
      model=\(self.modelIdentifier, privacy: .public)
      """)
    // Mirror to stderr for the macOS harness (ADR-013), same rationale as
    // `emitMaskedSelectionDiagnostic`.
    fputs(
      "samplerGrammarResample rejectedTokenId=\(rejectedToken) isEOG=\(isEOG) "
        + "position=\(diag.position) mode=\(diag.mode) model=\(modelIdentifier)\n",
      stderr)
  }

  /// Shared catch handling for both ``safeSample(handles:context:vocab:candidates:diag:)``
  /// branches. On a caught C++ exception from the bridge:
  ///   1. Truncate the captured `what()` to ~160 chars so the OSLog and
  ///      `LLMError.description` carriers stay readable.
  ///   2. Emit a `samplerCrashCaught` structured line on
  ///      `category:StreamingDiag` (always-on; see `samplerCatchDiagLogger`)
  ///      so the analyzer pipeline can aggregate occurrence rates across builds.
  ///      This line MUST keep firing once per catch — it is the
  ///      occurrence-rate telemetry — regardless of how callers handle the
  ///      thrown error.
  ///   3. Throw `LLMError.samplerCrashCaught`. As of #907 the generation
  ///      loops (`runGeneration` / `runStreamGeneration`) catch this error
  ///      and end generation gracefully instead of failing: the crash's
  ///      common trigger is the model continuing past a completed JSON
  ///      object with a token outside the grammar's ASCII trailing set, so
  ///      the completed object is already in the accumulated text — the
  ///      completed-object case wins outright, and the incomplete case
  ///      falls through to the parser's parse-failure retry (`LLMCaller`).
  ///      `LLMCaller` still routes the error through its retry budget (#885)
  ///      as defense in depth for any other surfacer, but the loops now
  ///      intercept the common case. The diagnostic above fires once per
  ///      catch so occurrence rates stay accurate.
  func handleSamplerCatch(_ errorMessage: String?, mode: String) throws {
    guard let errorMessage else { return }
    let truncated = String(errorMessage.prefix(160))
    // `truncated` is llama.cpp's grammar-accept `what()`; its canonical form
    // includes the just-sampled piece (`"after accepting piece: <piece> (<id>)"`),
    // which can be a mid-string fragment of model-generated content — keep it
    // `<private>` in TestFlight / Release per CLAUDE.md "Logger privacy". The
    // structured `mode` + `model` fields stay `.public` as postmortem pivot keys.
    Self.samplerCatchDiagLogger.error(
      """
      samplerCrashCaught what="\(truncated)" \
      mode=\(mode, privacy: .public) \
      model=\(self.modelIdentifier, privacy: .public)
      """)
    // Graceful stop, not fail-fast: the generation loops catch this and
    // end generation (the completed-object case wins; #907). The raw
    // `what()` rides in the associated value so any OTHER surfacer still
    // gets `LLMCaller`'s retry budget (#885) as defense in depth, and
    // `LLMError.errorDescription` formats it for display via the same
    // "Sampler crash caught: %@" catalog key.
    throw LLMError.samplerCrashCaught(description: truncated)
  }
}
