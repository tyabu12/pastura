import Foundation
import LlamaSwift

// MARK: - Pre-decode preparation

/// Outputs of ``LlamaCppService/prepareGeneration(model:context:system:user:schema:)``.
/// `vocab` is needed in the autoregressive loop (`llama_vocab_is_eog`,
/// piece decoding); `sampler` is the configured chain (penalties → top_k →
/// top_p → grammar → temperature → dist). The caller owns the sampler's
/// lifetime — see the precondition note on the helper itself.
nonisolated struct PreparedGeneration {
  /// Optional to match the upstream `llama_model_get_vocab` return type
  /// and the existing `tokenize` / `decodePiece` / `decodePieceRaw`
  /// signatures, which all accept `OpaquePointer?` directly without a
  /// nil check at the use site.
  let vocab: OpaquePointer?
  let sampler: UnsafeMutablePointer<llama_sampler>
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
  /// **Sampler ownership** — the returned `sampler` is owned by the
  /// caller. Pair every successful return with
  /// `defer { llama_sampler_free(prepared.sampler) }` in the caller's
  /// scope. The helper does NOT install its own defer because Swift's
  /// `defer` only fires at the helper's scope exit, which would free
  /// the sampler before the caller's inference loop runs.
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
  func prepareGeneration(
    model: OpaquePointer,
    context: OpaquePointer,
    system: String,
    user: String,
    schema: OutputSchema?
  ) throws -> PreparedGeneration {
    let vocab = llama_model_get_vocab(model)

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

    // Keep `createSampler` as the LAST step in this helper. The sampler
    // is freed by the caller's `defer { llama_sampler_free(...) }`; any
    // step added after this and before the return would leak the sampler
    // if it throws.
    let sampler = try createSampler(grammarString: grammarString, vocab: vocab)

    return PreparedGeneration(vocab: vocab, sampler: sampler)
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
