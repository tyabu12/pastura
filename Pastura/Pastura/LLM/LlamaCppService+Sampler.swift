import Foundation
import LlamaSwift
import os

// MARK: - Sampler

/// Chain + optional grammar handles produced by
/// ``LlamaCppService/createSampler(grammarString:vocab:antiRepetitionSeeds:)``.
///
/// The grammar is held **separately** from the chain (rather than as a
/// chain member) so ``LlamaCppService/safeSample(handles:context:vocab:candidates:diag:)``
/// can run the upstream `common_sampler_sample` two-pass strategy: sample
/// from the grammar-free chain, and only when the pick violates the
/// grammar, resample with the grammar applied FIRST. That split is what
/// avoids the dist-sampler degeneracy (#751 sub-class 2) — a grammar
/// mask applied after top_k's truncation can leave the sorted top
/// candidate at `-inf`, poisoning the softmax so the sampler picks a masked
/// token (empty output at position 0).
///
/// **Not a b8694 artifact — do not retire this split on the pin bump.**
/// `llama_sampler_dist_apply` is byte-identical between b8694 and the
/// current b10327 pin (measured on the upstream sources, #1487), including
/// the `if (!cur_p->sorted)` guard that is the whole mechanism: with
/// `sorted == true` the softmax takes `max_l` from `data[0]` alone, so a
/// masked top candidate makes every probability `NaN`.
///
/// **Ownership**: all three handles are caller-owned. Free `chain` **always**,
/// and `grammar` / `dry` when non-nil. Freeing the chain does NOT free the
/// split-out grammar or dry handles — they are not chain members, so
/// llama.cpp's chain-free does not reach them.
nonisolated struct SamplerHandles {
  let chain: UnsafeMutablePointer<llama_sampler>
  /// `nil` when no schema was supplied (unconstrained generation). Present
  /// iff the caller's `candidates` scratch buffer is present — the two are
  /// wired from the same `schema != nil` condition and must not drift.
  let grammar: UnsafeMutablePointer<llama_sampler>?
  /// DRY repetition sampler (#1105), seeded content-only with the agent's
  /// own prior statement so a token-level penalty spans the turn boundary.
  /// Why a second sampler at all: the chain's own `penalties` member is
  /// **within-generation only** — `createSampler` allocates a fresh chain per
  /// `generate()`, so its ring buffer starts empty and cannot see a prior turn.
  /// (It is live and load-bearing *inside* a generation — on this grammar path
  /// `acceptSampledToken` feeds it every accepted token — so do not remove it;
  /// it just cannot reach across the turn boundary, which is the scope #1105
  /// targets.) Held as a
  /// SEPARATE handle (like `grammar`, not a chain member) so seeding it via
  /// `llama_sampler_accept` does NOT feed the chain's `penalties` ring buffer
  /// — that would silently blend a second penalty into an A/B arm. Also
  /// `nil` unless a grammar is active: DRY is gated on `schema != nil` (same
  /// condition as `grammar` / `candidates`), so the bundled no-grammar path
  /// never carries it. Applied in ``fillApplyAndSelect`` and advanced in
  /// ``acceptSampledToken``.
  let dry: UnsafeMutablePointer<llama_sampler>?
}

extension LlamaCppService {
  /// Build the llama.cpp sampler chain, plus an optional GBNF grammar
  /// handle held separately from the chain (see ``SamplerHandles``).
  ///
  /// - Parameters:
  ///   - grammarString: Pre-built GBNF from ``GBNFGrammarBuilder``. When
  ///     non-nil, a `llama_sampler_init_grammar` handle is built and
  ///     returned alongside the chain (NOT inserted into it).
  ///   - vocab: The model's vocabulary pointer. **Unconditionally required**
  ///     since the b10327 pin: `llama_sampler_init_penalties` gained an
  ///     `n_vocab` argument, and `penalties` is a chain member on *both* the
  ///     grammar and no-grammar paths — so vocab is no longer needed only by
  ///     the grammar parser. Non-optional rather than guarded, because
  ///     `llama_vocab_n_tokens(nil)` dereferences NULL rather than throwing.
  ///   - antiRepetitionSeeds: Prior text spans to seed the DRY sampler with
  ///     (content-only — the value text, never JSON scaffold). Empty leaves DRY
  ///     off, so the sampler is byte-for-byte the pre-#1105 configuration.
  ///     Enablement otherwise is `DryConfig`'s call — do not restate it here.
  ///
  /// **Chain order**: `penalties → top_k → top_p → temperature → dist`.
  /// The grammar and DRY are applied outside the chain by `safeSample`
  /// (grammar-first only on a resample; DRY every pass), matching llama.cpp's
  /// `common_sampler_sample`. DRY is a SOFT penalty (never `-inf`), so
  /// applying it before top_k cannot manufacture the all-masked
  /// degeneracy that motivated splitting the grammar out (#751).
  ///
  /// **Call sites**: both `runGeneration` (non-streaming) and
  /// `runStreamGeneration` (streaming) call this via `prepareGeneration`.
  /// A third caller must always supply `vocab`, and pass `grammarString`
  /// whenever its path has a schema — omitting it silently bypasses grammar
  /// on that path, the exact regression this plan's Critic Axis 3 flagged.
  /// The old "pass `nil` for both" escape is gone: `vocab` no longer tracks
  /// `grammarString`'s presence.
  ///
  /// - Throws: ``LLMError/invalidGrammar(description:)`` if
  ///   `llama_sampler_init_grammar` returns NULL (unparseable GBNF —
  ///   a caller-side / builder bug; see ``LLMError/invalidGrammar``).
  func createSampler(
    grammarString: String? = nil,
    vocab: OpaquePointer,
    antiRepetitionSeeds: [String] = []
  ) throws -> SamplerHandles {
    let sparams = llama_sampler_chain_default_params()
    guard let chain = llama_sampler_chain_init(sparams) else {
      throw LLMError.generationFailed(description: "Failed to initialize sampler chain")
    }

    // Chain order: penalties → top_k → top_p → temperature → dist. The
    // grammar is deliberately NOT a chain member — it is returned as a
    // separate handle so `safeSample` can run the upstream
    // `common_sampler_sample` two-pass strategy (sample from the chain,
    // grammar-check the pick, resample grammar-first only on a miss). A
    // grammar stage inside the chain would run AFTER top_k's truncation,
    // reintroducing the dist-degeneracy that masks the sorted top
    // candidate and poisons the softmax (#751 sub-class 2).
    llama_sampler_chain_add(
      chain,
      llama_sampler_init_penalties(
        llama_vocab_n_tokens(vocab),  // n_vocab: added by b10327 (see `vocab` param)
        64,  // penalty_last_n: look back 64 tokens
        Self.repeatPenalty,  // repeat_penalty: 1.1
        0.0,  // freq_penalty: disabled
        0.0  // presence_penalty: disabled
      ))
    llama_sampler_chain_add(chain, llama_sampler_init_top_k(Self.topK))
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(Self.topP, 1))
    llama_sampler_chain_add(chain, llama_sampler_init_temp(Self.temperature))
    llama_sampler_chain_add(
      chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

    guard let grammarString else {
      // No grammar → no DRY (gated on `schema != nil`, mirroring
      // `makeCandidateBuffer`). The bundled no-grammar path samples through
      // `llama_sampler_sample`, which builds `cur_p` internally with no seam
      // to apply a separate DRY handle — and no seeded caller reaches it
      // (seeds flow only from schema-bearing LLM phases). See #1105.
      //
      // This return is upstream of `buildAndSeedDrySampler`, so without a
      // marker here a whole run could emit zero `samplerDry*` lines for a
      // healthy reason — indistinguishable from an instrument that never
      // fired (#1483).
      //
      // Keep the emit ABOVE `initGrammarCapturingStderr` below: that helper
      // dup2s fd 2 for the width of one C call, so a marker moved under it
      // would be swallowed into the grammar-parse capture instead of the
      // harness sidecar. Nothing tests this ordering.
      emitDryUnavailable(.noGrammar)
      return SamplerHandles(chain: chain, grammar: nil, dry: nil)
    }
    // `llama_sampler_init_grammar` returns NULL when the grammar
    // string itself fails to parse. GBNFGrammarBuilder golden tests
    // should prevent this reaching production, but if it does we
    // want fail-fast, NOT the 3x-retry charade `.generationFailed`
    // would trigger via LLMCaller (Critic Axis 11).
    let (grammarSamplerOpt, capturedStderr) = grammarString.withCString { cStr in
      initGrammarCapturingStderr(vocab: vocab, grammarCString: cStr)
    }
    guard let grammarSampler = grammarSamplerOpt else {
      llama_sampler_free(chain)
      // Log the FULL grammar at error level so Console.app captures it
      // verbatim — the `invalidGrammar` error's description field is
      // rendered in iOS alerts where backslashes / quotes are mangled.
      // Append captured stderr (the parser-internal detail from
      // llama-grammar.cpp:715) wrapped in sentinel markers so unrelated
      // process-level stderr writes during the capture window are
      // visually attributable rather than mistaken for grammar errors.
      // Filter:  subsystem:app.pastura.Pastura category:LlamaCppService
      //          message contains "GBNF grammar parse failed"
      logger.error(
        """
        GBNF grammar parse failed — llama_sampler_init_grammar returned NULL.
        <<<BEGIN GBNF>>>
        \(grammarString, privacy: .public)
        <<<END GBNF>>>
        --- BEGIN llama.cpp stderr capture (process-wide window — may include unrelated writers) ---
        \(capturedStderr, privacy: .public)
        --- END capture ---
        """)
      let snippet = grammarString.prefix(200)
      throw LLMError.invalidGrammar(
        description: String(
          format: String(localized: "GBNF grammar parse failed: %@"), String(snippet)))
    }
    // DRY repetition sampler (#1105), built here so it shares the grammar's
    // `schema != nil` gate. `nil` when no seeds are supplied; enablement
    // otherwise is `DryConfig`'s call — do not restate it here. When `dry` is
    // nil the sampler is the pre-#1105 configuration.
    let drySampler = buildAndSeedDrySampler(
      vocab: vocab, seeds: antiRepetitionSeeds)
    return SamplerHandles(chain: chain, grammar: grammarSampler, dry: drySampler)
  }

  /// Allocate the reused per-generation candidate scratch buffer for the
  /// grammar-constrained sampling path, or `nil` when no grammar is active.
  ///
  /// When a grammar is active,
  /// ``safeSample(handles:context:vocab:candidates:diag:)`` rebuilds a
  /// full-vocab `cur_p` from the raw logits each token (twice on a
  /// resample), which needs an `n_vocab`-sized buffer. Allocated once per
  /// generation and reused across the token loop. Returns `nil` when
  /// `schema == nil` (no grammar built — the bundled path needs no buffer),
  /// mirroring the `createSampler` grammar-build condition so the buffer and
  /// the ``SamplerHandles/grammar`` handle cannot drift.
  ///
  /// - Important: ownership stays with the caller — the buffer's lifetime is
  ///   the whole generation, so the caller MUST `deallocate()` it (via
  ///   `defer`). Returning it (rather than taking a closure) keeps the
  ///   `defer` adjacent to the token loop it guards.
  func makeCandidateBuffer(
    schema: OutputSchema?, vocab: OpaquePointer
  ) -> UnsafeMutableBufferPointer<llama_token_data>? {
    guard schema != nil else { return nil }
    return .allocate(capacity: Int(llama_vocab_n_tokens(vocab)))
  }

  /// Sample the next token, dispatching on whether a grammar is active.
  ///
  /// - No grammar (`candidates == nil`): the bundled
  ///   ``SafeSampler/sample(sampler:context:idx:)`` runs unchanged — with no
  ///   grammar there is nothing for an EOG accept to abort, and the bundled
  ///   path reuses llama's internal candidate buffer.
  /// - Grammar active (`candidates != nil`): delegates to the two-pass
  ///   ``grammarConstrainedSample(handles:context:vocab:candidates:diag:)``,
  ///   which keeps the #253 EOG-accept skip and adds the #751 sub-class 2
  ///   grammar-first resample.
  ///
  /// Catch path: the grammar `accept_token` `std::runtime_error`
  /// (#334 / #366 / #371) surfaces as ``SafeSampler/Outcome/errorMessage``
  /// and is routed through ``handleSamplerCatch(_:mode:)`` (diagnostic +
  /// `LLMError.samplerCrashCaught`). The generation loops catch that as
  /// end-of-generation (`nextContentTokenOrStop`, #907).
  ///
  /// - Parameters:
  ///   - handles: chain + optional grammar handle from `createSampler`.
  ///     `handles.grammar` is non-nil iff `candidates` is non-nil.
  ///   - vocab: model vocab pointer, for EOG classification.
  ///   - candidates: caller-owned, `n_vocab`-sized scratch buffer reused
  ///     across the token loop. `nil` selects the bundled fast path.
  ///   - diag: per-token diagnostic context (`mode` loop tag + generation
  ///     `position`) for the always-on sampler telemetry; see
  ///     ``SamplerDiagContext``.
  func safeSample(
    handles: SamplerHandles, context: OpaquePointer,
    vocab: OpaquePointer?,
    candidates: UnsafeMutableBufferPointer<llama_token_data>?,
    diag: SamplerDiagContext
  ) throws -> Int32 {
    guard let candidates else {
      // No grammar active: the bundled sample+accept cannot hit the #253
      // grammar abort (no grammar to accept into), and reuses llama's
      // internal candidate buffer — keep the simpler, allocation-free path.
      let outcome = SafeSampler.sample(sampler: handles.chain, context: context, idx: -1)
      try handleSamplerCatch(outcome.errorMessage, mode: diag.mode)
      return outcome.token
    }
    return try grammarConstrainedSample(
      handles: handles, context: context,
      vocab: vocab, candidates: candidates, diag: diag)
  }

  /// Call `llama_sampler_init_grammar` with stderr redirected to a `Pipe`
  /// so the parser-internal error message is captured for diagnostics.
  ///
  /// **Why dup2 is needed.** llama.cpp's grammar parser writes detailed
  /// errors via `fprintf(stderr, "error parsing grammar: %s\n\n%s\n", ...)`
  /// at `llama-grammar.cpp:715` (b10327), then `parser.parse` returns false.
  /// Only the outer `LLAMA_LOG_ERROR("failed to parse grammar")` — same file,
  /// line 1223 at that pin — reaches our `llama_log_set` callback
  /// (`LlamaCppService.swift`).
  /// iOS doesn't pipe process stderr to os_log, so without this `dup2`
  /// redirect the actionable detail (`expecting ']' at`,
  /// `Undefined rule identifier 'X'`, etc.) is permanently lost.
  ///
  /// **Bounds.** Worst-case `fprintf` payload is grammar-source (~1–2KB)
  /// + parser error (~100B) per call; pipe capacity is 64KB on Darwin.
  /// Safe within the single `init_grammar` window. Per-call success-path
  /// overhead is ~30–70µs (one `Pipe()`, three fd syscalls, and an empty
  /// `readToEnd`); fd churn is 4 per call, well within iOS sandbox limits
  /// (~256 soft limit). Widening the redirect window invalidates the
  /// 64KB-payload bound.
  ///
  /// **Process-wide caveat.** `dup2(_, STDERR_FILENO)` is process-wide;
  /// any thread writing to stderr during the (short) capture window has
  /// its bytes captured too. The single-`init_grammar` window keeps this
  /// tight. Captured noise is wrapped in sentinel markers at the call
  /// site (see `createSampler`) so unrelated bytes are visually
  /// attributable rather than mistaken for grammar errors. `llama_log_set`
  /// uses unified-logging mach IPC, not stderr, so its capture pipeline
  /// is independent of the dup2 redirect here.
  ///
  /// **Failure modes.** If `dup` or `dup2` fails (rare — EMFILE/ENFILE
  /// under fd pressure), this falls through to a no-capture path: a
  /// `logger.warning` is emitted with the errno, `init_grammar` is called
  /// without redirection, and a sentinel string is returned in place of
  /// captured bytes so the absence of capture is positively logged
  /// (a future debugger doesn't have to infer it from missing output).
  /// Never `dup2(-1, STDERR_FILENO)` — that would permanently invalidate
  /// fd 2 process-wide and SIGPIPE the next `fprintf`.
  ///
  /// - Returns: `(sampler, capturedStderr)` where `sampler` is the
  ///   llama.cpp sampler pointer (`nil` on grammar parse failure) and
  ///   `capturedStderr` is the (possibly empty) stderr payload, decoded
  ///   strictly as UTF-8 with a hex-prefix fallback when invalid bytes
  ///   are present (`String(bytes:encoding:)` is failable, not lossy —
  ///   the fallback is what handles non-UTF-8). Or a
  ///   `"<stderr capture skipped: …>"` sentinel when redirect setup failed.
  private func initGrammarCapturingStderr(
    vocab: OpaquePointer,
    grammarCString: UnsafePointer<CChar>
  ) -> (sampler: UnsafeMutablePointer<llama_sampler>?, capturedStderr: String) {
    let savedStderr = dup(STDERR_FILENO)
    guard savedStderr >= 0 else {
      let dupErrno = errno
      logger.warning(
        "stderr capture skipped: dup(STDERR_FILENO) failed errno=\(dupErrno)")
      return (
        llama_sampler_init_grammar(vocab, grammarCString, "root"),
        "<stderr capture skipped: dup failed errno=\(dupErrno)>"
      )
    }

    let pipe = Pipe()
    fflush(stderr)
    guard
      dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0
    else {
      let dupErrno = errno
      logger.warning(
        "stderr capture skipped: dup2 failed errno=\(dupErrno)")
      close(savedStderr)
      try? pipe.fileHandleForReading.close()
      try? pipe.fileHandleForWriting.close()
      return (
        llama_sampler_init_grammar(vocab, grammarCString, "root"),
        "<stderr capture skipped: dup2 failed errno=\(dupErrno)>"
      )
    }

    // Instrumented call: fd 2 and pipe.fileHandleForWriting both reference
    // the pipe writer; any fprintf(stderr, ...) by llama.cpp lands here.
    let sampler = llama_sampler_init_grammar(vocab, grammarCString, "root")
    fflush(stderr)

    // Drain order is load-bearing — `defer` does NOT work for this pattern
    // because `readToEnd` blocks until ALL writers close, and our two
    // writers (fd 2 and pipe.fileHandleForWriting) must both close BEFORE
    // the read, which means before scope exit:
    //   1. `dup2(savedStderr, …)` — drops fd 2's reference to the pipe writer.
    //   2. close `pipe.fileHandleForWriting` — drops the second writer reference.
    //   3. read.
    //   4. cleanup remaining fds.
    // Skipping step 2 leaves `readToEnd` blocked indefinitely.
    //
    // The restore `dup2` is checked symmetrically with the setup `dup2`
    // (EBADF is the only realistic failure since `savedStderr` was just
    // `dup`'d above and `STDERR_FILENO` is a valid target — but a silent
    // failure here would leave fd 2 pointing at the about-to-close pipe
    // writer, SIGPIPE-ing the next process-wide `fprintf(stderr, …)`).
    if dup2(savedStderr, STDERR_FILENO) < 0 {
      let restoreErrno = errno
      logger.error(
        "stderr restore (dup2) failed errno=\(restoreErrno) — fd 2 may be invalid")
    }
    try? pipe.fileHandleForWriting.close()
    let captured = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
    close(savedStderr)
    try? pipe.fileHandleForReading.close()

    // Decode captured bytes as UTF-8. The realistic content is ASCII
    // (parser error message + grammar source which our builder produces),
    // but if non-UTF-8 bytes do sneak in (unrelated process-level stderr
    // writers in the dup2 window) we surface byte-count + hex prefix
    // rather than silently dropping the entire diagnostic.
    let stderrString =
      String(bytes: captured, encoding: .utf8)
      ?? "<non-UTF-8 stderr capture: \(captured.count) bytes; "
      + "hex prefix: "
      + captured.prefix(64).map { String(format: "%02x", $0) }.joined() + ">"
    return (sampler, stderrString)
  }
}
