import Foundation
import LlamaSwift

// MARK: - Grammar-constrained two-pass sampling (#751)

extension LlamaCppService {
  /// Grammar-constrained token sampling, mirroring llama.cpp's
  /// `common_sampler_sample` (upstream `common/sampling.cpp`) two-pass
  /// strategy — the fix for #751 sub-class 2 (empty output / masked
  /// selection).
  ///
  /// **Why two passes.** The grammar is held OUTSIDE the sampler chain (see
  /// ``SamplerHandles``). A single-pass "grammar inside the chain" runs the
  /// grammar mask AFTER top_k's truncation; `llama_sampler_dist_apply`
  /// then degenerates when the sorted top candidate is masked (`max_l =
  /// data[0].logit = -inf` → NaN/`exp(+inf)` softmax) or when every truncated
  /// candidate is masked (all-NaN scan, `assert(found)` compiled out of the
  /// release xcframework) — either way it silently selects a grammar-invalid
  /// token, which at position 0 becomes empty output. Splitting the grammar
  /// out and applying it grammar-FIRST on the resample lets top_k re-sort on
  /// the masked logits, so `data[0]` is always grammar-valid.
  ///
  /// **The passes:**
  /// 1. Sample from the grammar-free chain (`penalties → top_k → top_p →
  ///    temp → dist`). If the pick already satisfies the grammar (the common
  ///    case — the model's top token is grammar-valid), accept and return it.
  ///    A single-token grammar `apply` is side-effect-free (apply only reads
  ///    the grammar stacks; only `accept` mutates them), so this probe never
  ///    desyncs grammar state.
  /// 2. On a grammar miss, resample: re-fill full-vocab logits, apply the
  ///    grammar FIRST (masking invalid tokens), then the chain. `data[0]` is
  ///    grammar-valid, so the dist degeneracy cannot recur.
  ///
  /// **Terminal branch.** If the grammar-first pass ALSO lands on a masked
  /// token, the grammar admits nothing here (all tokens masked, incl. EOG) —
  /// a genuinely dead grammar state, distinct from the recoverable #751 case.
  /// Rather than let the dist fallthrough emit garbage, stop gracefully at
  /// EOS. Unreachable at position 0 for the shipped profiles (their vocabs
  /// all contain a bare `{`); defensive only.
  ///
  /// **Accept discipline.** On a returned (non-terminal) token, the grammar
  /// handle is advanced for every non-EOG token (EOG is skipped — the #253
  /// post-EOG `GGML_ABORT`), and the chain is always advanced so its
  /// penalties ring buffer tracks the emitted token. The grammar `accept`
  /// can throw the `Unexpected empty grammar stack` `std::runtime_error`
  /// (#334) and is routed through ``handleSamplerCatch(_:mode:)``; the chain
  /// `accept` has no grammar member and cannot abort.
  func grammarConstrainedSample(
    handles: SamplerHandles,
    context: OpaquePointer,
    vocab: OpaquePointer?,
    candidates: UnsafeMutableBufferPointer<llama_token_data>,
    diag: SamplerDiagContext
  ) throws -> Int32 {
    let chain = handles.chain
    guard let grammar = handles.grammar else {
      // Programming error: a candidate buffer was allocated (schema present)
      // but no grammar handle came back. `makeCandidateBuffer` and
      // `createSampler` key off the same `schema != nil`, so this is
      // unreachable — surface it loudly rather than silently mis-sample.
      throw LLMError.generationFailed(
        description: "grammarConstrainedSample: candidate buffer present without a grammar handle")
    }
    guard let base = candidates.baseAddress, !candidates.isEmpty else {
      throw LLMError.generationFailed(
        description: String(localized: "Sampler candidate buffer is empty"))
    }
    let count = candidates.count

    // Pass 1: grammar-free chain sample.
    let firstPick = try fillApplyAndSelect(
      chain: chain, grammarFirst: nil, dry: handles.dry, context: context,
      base: base, count: count)
    if tokenSatisfiesGrammar(firstPick.id, grammar: grammar) {
      try acceptSampledToken(
        firstPick.id, chain: chain, grammar: grammar, dry: handles.dry,
        vocab: vocab, mode: diag.mode)
      return firstPick.id
    }

    // Pass 1 missed the grammar — telemetry for the model-onboarding
    // pipeline: a nonzero position-0 resample rate is the empty-output
    // fragility signal (weak JSON prior, e.g. Sarashina). Rescued here, not
    // failed. Off the hot path (only fires when a resample is actually
    // needed).
    emitGrammarResampleDiagnostic(rejectedToken: firstPick.id, vocab: vocab, diag: diag)

    // Pass 2: grammar FIRST, then the chain.
    let resampled = try fillApplyAndSelect(
      chain: chain, grammarFirst: grammar, dry: handles.dry, context: context,
      base: base, count: count)

    // Terminal: even the grammar-first pass selected a masked token → dead
    // grammar. Stop generation (no accept). Return EOS so
    // `nextContentTokenOrStop`'s `is_eog` check maps it to a clean stop.
    // Guard the vocab-has-no-EOS case: `llama_vocab_eos` returns
    // `LLAMA_TOKEN_NULL` (< 0) then, and `is_eog(-1)` is false — a raw -1
    // would leak into the decode path as a "content" token. Route that
    // (doubly-unreachable: dead grammar AND no EOS) through the graceful
    // stop channel instead. All shipped profiles define an EOS.
    if resampled.logit == -Float.infinity {
      emitMaskedSelectionDiagnostic(
        token: resampled.id, curP: resampled.array, vocab: vocab, diag: diag)
      let eos = llama_vocab_eos(vocab)
      guard eos >= 0 else {
        throw LLMError.samplerCrashCaught(
          description: "grammar admits no token and vocab defines no EOS")
      }
      return eos
    }

    try acceptSampledToken(
      resampled.id, chain: chain, grammar: grammar, dry: handles.dry,
      vocab: vocab, mode: diag.mode)
    return resampled.id
  }

  /// The result of one apply-and-select pass: the selected token id, its
  /// post-apply logit (`-inf` iff grammar-masked), and the `cur_p` array it
  /// was chosen from (for diagnostics).
  nonisolated private struct SelectedToken {
    let id: Int32
    let logit: Float
    let array: llama_token_data_array
  }

  /// Rebuild a full-vocab `cur_p` from the context's latest logits, apply
  /// the grammar first (when `grammarFirst` is non-nil), then the chain, and
  /// return the selected token. Fills `base[0..<count]` fresh each call so a
  /// prior pass's truncation/reordering can't leak across the reused buffer.
  private func fillApplyAndSelect(  // swiftlint:disable:this function_parameter_count
    chain: UnsafeMutablePointer<llama_sampler>,
    grammarFirst: UnsafeMutablePointer<llama_sampler>?,
    dry: UnsafeMutablePointer<llama_sampler>?,
    context: OpaquePointer,
    base: UnsafeMutablePointer<llama_token_data>,
    count: Int
  ) throws -> SelectedToken {
    guard let logits = llama_get_logits_ith(context, -1) else {
      throw LLMError.generationFailed(
        description: String(localized: "Sampler produced no logits"))
    }
    for i in 0..<count {
      base[i] = llama_token_data(id: Int32(i), logit: logits[i], p: 0)
    }
    // `selected = -1` so a stale index can't leak; the chain's terminal dist
    // sampler sets it. `apply` never mutates grammar state (only `accept`
    // does), so applying the grammar here is side-effect-free.
    //
    // Order: grammar (hard `-inf` mask) → DRY (soft repetition penalty) →
    // chain (penalties → top_k → … → dist). DRY runs before top_k like the
    // chain's own `penalties` member; because it is a SOFT penalty it never
    // produces `-inf`, so it cannot manufacture the all-masked
    // degeneracy — that hazard is grammar-only (#751 / #1105).
    var curP = llama_token_data_array(data: base, size: count, selected: -1, sorted: false)
    if let grammarFirst {
      llama_sampler_apply(grammarFirst, &curP)
    }
    if let dry {
      llama_sampler_apply(dry, &curP)
    }
    llama_sampler_apply(chain, &curP)
    guard curP.selected >= 0, curP.selected < Int64(curP.size), let data = curP.data else {
      throw LLMError.generationFailed(
        description: String(localized: "Sampler produced no selection"))
    }
    let picked = data[Int(curP.selected)]
    return SelectedToken(id: picked.id, logit: picked.logit, array: curP)
  }

  /// Whether `token` is grammar-valid at the current grammar state. Applies
  /// the grammar to a single-element `cur_p`; a `-inf` result means masked.
  /// Side-effect-free on the grammar (apply reads stacks, only accept
  /// mutates), so this probe never advances or desyncs grammar state.
  private func tokenSatisfiesGrammar(
    _ token: Int32, grammar: UnsafeMutablePointer<llama_sampler>
  ) -> Bool {
    var single = llama_token_data(id: token, logit: 0, p: 0)
    return withUnsafeMutablePointer(to: &single) { ptr in
      var arr = llama_token_data_array(data: ptr, size: 1, selected: -1, sorted: false)
      llama_sampler_apply(grammar, &arr)
      return ptr.pointee.logit != -Float.infinity
    }
  }

  /// Advance the grammar (non-EOG only — #253) and the chain (always, for
  /// penalties continuity) on the accepted token. Routes the grammar accept
  /// through the C++ catch shim (#334); the chain accept cannot throw.
  private func acceptSampledToken(  // swiftlint:disable:this function_parameter_count
    _ token: Int32,
    chain: UnsafeMutablePointer<llama_sampler>,
    grammar: UnsafeMutablePointer<llama_sampler>,
    dry: UnsafeMutablePointer<llama_sampler>?,
    vocab: OpaquePointer?,
    mode: String
  ) throws {
    if !llama_vocab_is_eog(vocab, token) {
      let outcome = SafeSampler.accept(sampler: grammar, token: token)
      try handleSamplerCatch(outcome.errorMessage, mode: mode)
    }
    _ = SafeSampler.accept(sampler: chain, token: token)
    // Advance DRY too so its running n-gram context tracks the emitted
    // tokens (continuing from the seeded prior statement). A DRY accept is a
    // ring-buffer push with no grammar member — it cannot throw the #334
    // crash, so no SafeSampler wrapping / EOG guard is needed.
    if let dry {
      llama_sampler_accept(dry, token)
    }
  }
}
