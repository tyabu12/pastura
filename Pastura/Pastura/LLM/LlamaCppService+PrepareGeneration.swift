import Foundation
import LlamaSwift

// MARK: - Pre-decode preparation

/// Outputs of ``LlamaCppService/prepareGeneration(model:context:system:user:schema:)``.
/// `vocab` is needed in the autoregressive loop (`llama_vocab_is_eog`,
/// piece decoding); `handles` bundles the configured chain (penalties →
/// top_k → top_p → temperature → dist) and the optional grammar handle held
/// separately from it (see ``SamplerHandles``). The caller owns both
/// handles' lifetimes — see the precondition note on the helper itself.
nonisolated struct PreparedGeneration {
  /// Non-optional since the b10327 pin: `prepareGeneration` unwraps
  /// `llama_model_get_vocab` up front, because the sampler chain now needs
  /// `n_vocab` and `llama_vocab_n_tokens(nil)` dereferences NULL rather than
  /// returning 0. Keeping it optional would leave that invariant asserted only
  /// in prose while `makeCandidateBuffer` passed the optional straight into
  /// the same C call. The `tokenize` / `decodePiece` / `decodePieceRaw`
  /// signatures still take `OpaquePointer?` and need no change — Swift
  /// promotes `T` to `T?` at the call site.
  let vocab: OpaquePointer
  let handles: SamplerHandles
}

extension LlamaCppService {
  /// Shared pre-decode pipeline for ``runGeneration`` (non-streaming) and
  /// ``runStreamGeneration`` (streaming). Runs: vocab derive → chat
  /// template apply → tokenize → context-size bound check → KV cache
  /// clear → prefill → grammar build → sampler chain create.
  ///
  /// **Preconditions** (load-bearing — caller responsibilities not
  /// re-checked here):
  /// 1. Caller holds ``generatingGuard`` via
  ///    ``acquireGenerateGuard(caller:)`` (ADR-002 §6 sequential-access
  ///    contract). The guard prevents `unloadModel` from freeing
  ///    `model` / `context` between this call and the caller's inference
  ///    loop.
  /// 2. Caller has already verified `isModelLoaded` and captured `model`
  ///    / `context` from `_model` / `_context` after that check. This
  ///    helper accepts the captured pointers directly because the
  ///    private storage is not visible to sibling-file extensions.
  ///
  /// **Sampler ownership** — the returned `handles` are owned by the
  /// caller. Pair every successful return with
  /// `defer { llama_sampler_free(prepared.handles.chain) }`,
  /// `defer { prepared.handles.grammar.map { llama_sampler_free($0) } }`
  /// AND `defer { prepared.handles.dry.map { llama_sampler_free($0) } }`
  /// in the caller's scope — all three, as both existing callers do. The
  /// `dry` handle (#1105) is as separate an allocation as `grammar`; a caller
  /// following an earlier two-defer version of this list leaks it.
  /// The helper does NOT install its own defer
  /// because Swift's `defer` only fires at the helper's scope exit, which
  /// would free the handles before the caller's inference loop runs.
  /// The split-out grammar is a separate allocation — freeing the chain
  /// does not reach it (see ``SamplerHandles``).
  ///
  /// **Grammar wire-up** — both calling paths get grammar through this
  /// single seam when `schema` is non-nil. If a third call path is
  /// added, route it through this helper rather than reconstructing the
  /// sampler inline; missing grammar wire-up on the streaming path was
  /// the regression class Critic Axis 3 flagged when this helper was
  /// proposed (see issue #428 for the dedup rationale).
  ///
  /// - Throws: ``LLMError/generationFailed(description:)`` when the
  ///   prompt token count exceeds the context size; whatever
  ///   ``applyChatTemplate``, ``tokenize``, ``prefill``, or
  ///   ``createSampler`` throw.
  func prepareGeneration(  // swiftlint:disable:this function_parameter_count
    model: OpaquePointer,
    context: OpaquePointer,
    system: String,
    user: String,
    schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) throws -> PreparedGeneration {
    // Unwrapped here rather than at the `createSampler` call: since the
    // b10327 pin, `vocab` is a hard requirement of the sampler chain itself
    // (`llama_sampler_init_penalties` takes `n_vocab`), and
    // `llama_vocab_n_tokens(nil)` dereferences NULL rather than returning 0.
    // `.notLoaded` rather than a new key: a loaded model always has a vocab,
    // so NULL here means the model is not actually usable.
    guard let vocab = llama_model_get_vocab(model) else { throw LLMError.notLoaded }

    let formattedPrompt = try applyChatTemplate(system: system, user: user)
    let tokens = try tokenize(vocab: vocab, text: formattedPrompt, addSpecial: true)

    let nCtx = Int(llama_n_ctx(context))
    guard tokens.count <= nCtx else {
      throw LLMError.generationFailed(
        description: String(
          format: String(localized: "Prompt (%lld tokens) exceeds context size (%lld)"),
          tokens.count, nCtx)
      )
    }

    // Clear KV cache for independent inference (each generate() call is self-contained).
    llama_memory_clear(llama_get_memory(context), true)

    try prefill(context: context, tokens: tokens)

    // Build grammar once per call when a schema is requested.
    let grammarString = try schema.map { try GBNFGrammarBuilder().build(from: $0) }

    // Keep `createSampler` as the LAST step in this helper. The handles
    // are freed by the caller's `defer`s; any step added after this and
    // before the return would leak the chain / grammar / dry if it throws.
    let handles = try createSampler(
      grammarString: grammarString, vocab: vocab,
      antiRepetitionSeeds: antiRepetitionSeeds)

    return PreparedGeneration(vocab: vocab, handles: handles)
  }

  /// Shared empty-output postcondition for both `runGeneration` paths.
  /// Centralizing the throw keeps the catalog key
  /// `"Model generated no output tokens"` at a single source location.
  func assertNonEmptyOutput(_ text: String) throws {
    guard !text.isEmpty else {
      throw LLMError.generationFailed(
        description: String(localized: "Model generated no output tokens"))
    }
  }
}
