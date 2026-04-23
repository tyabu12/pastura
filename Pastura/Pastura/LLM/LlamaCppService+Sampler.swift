import Foundation
import LlamaSwift

// MARK: - Sampler

extension LlamaCppService {
  /// Build the llama.cpp sampler chain, optionally constrained by a GBNF
  /// grammar string.
  ///
  /// - Parameters:
  ///   - grammarString: Pre-built GBNF from ``GBNFGrammarBuilder``. When
  ///     non-nil, a `llama_sampler_init_grammar` stage is inserted into
  ///     the chain to mask the logits to grammar-valid tokens before
  ///     temperature smoothing.
  ///   - vocab: The model's vocabulary pointer. Required iff
  ///     `grammarString` is non-nil — the grammar parser needs it to
  ///     resolve token IDs.
  ///
  /// **Chain order**: `penalties → top_k → top_p → grammar → temperature → dist`.
  /// Grammar is placed BEFORE temperature per llama.cpp upstream
  /// convention (see `common/sampling.cpp`): hard-constraint masking on
  /// the raw logits first, then temperature smoothing on the narrowed
  /// distribution, then distribution sampling. Putting grammar after
  /// temperature would re-weight grammar-invalid tokens the masker
  /// already zeroed out — correct but wasteful.
  ///
  /// **Call sites**: both `runGeneration` (non-streaming) and
  /// `runStreamGeneration` (streaming) call this. If you add a third
  /// caller, wire the `grammarString` / `vocab` pair or explicitly pass
  /// `nil` for both — missing one side silently bypasses grammar on the
  /// path the new caller exercises, the exact regression this plan's
  /// Critic Axis 3 flagged.
  ///
  /// - Throws: ``LLMError/invalidGrammar(description:)`` if
  ///   `llama_sampler_init_grammar` returns NULL (unparseable GBNF —
  ///   a caller-side / builder bug; see ``LLMError/invalidGrammar``).
  func createSampler(
    grammarString: String? = nil,
    vocab: OpaquePointer? = nil
  ) throws -> UnsafeMutablePointer<llama_sampler> {
    let sparams = llama_sampler_chain_default_params()
    guard let chain = llama_sampler_chain_init(sparams) else {
      throw LLMError.generationFailed(description: "Failed to initialize sampler chain")
    }

    // Order: penalties → top_k → top_p → grammar → temperature → dist
    // Penalties on full vocab first, then narrow, then grammar mask,
    // then temperature, then selection. See llama.cpp upstream
    // `common/sampling.cpp` for reference chains.
    llama_sampler_chain_add(
      chain,
      llama_sampler_init_penalties(
        64,  // penalty_last_n: look back 64 tokens
        Self.repeatPenalty,  // repeat_penalty: 1.1
        0.0,  // freq_penalty: disabled
        0.0  // presence_penalty: disabled
      ))
    llama_sampler_chain_add(chain, llama_sampler_init_top_k(Self.topK))
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(Self.topP, 1))

    if let grammarString {
      guard let vocab else {
        // Defensive: if the caller supplies grammar but forgets vocab, we
        // can't wire the grammar sampler. This is a programming bug,
        // surface it loudly via the same fail-fast path as a NULL return.
        llama_sampler_free(chain)
        throw LLMError.invalidGrammar(
          description: "createSampler: grammar supplied without vocab")
      }
      // `llama_sampler_init_grammar` returns NULL when the grammar
      // string itself fails to parse. GBNFGrammarBuilder golden tests
      // should prevent this reaching production, but if it does we
      // want fail-fast, NOT the 3x-retry charade `.generationFailed`
      // would trigger via LLMCaller (Critic Axis 11).
      let grammarStringPtr = grammarString
      guard
        let grammarSampler = grammarStringPtr.withCString({ cStr in
          llama_sampler_init_grammar(vocab, cStr, "root")
        })
      else {
        llama_sampler_free(chain)
        let snippet = grammarString.prefix(200)
        throw LLMError.invalidGrammar(
          description: "GBNF grammar parse failed: \(snippet)")
      }
      llama_sampler_chain_add(chain, grammarSampler)
    }

    llama_sampler_chain_add(chain, llama_sampler_init_temp(Self.temperature))
    llama_sampler_chain_add(
      chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

    return chain
  }
}
