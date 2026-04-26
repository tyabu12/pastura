import Foundation
import LlamaSwift
import os

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
      let (grammarSamplerOpt, capturedStderr) = grammarString.withCString { cStr in
        initGrammarCapturingStderr(vocab: vocab, grammarCString: cStr)
      }
      guard let grammarSampler = grammarSamplerOpt else {
        llama_sampler_free(chain)
        // Log the FULL grammar at error level so Console.app captures it
        // verbatim — the `invalidGrammar` error's description field is
        // rendered in iOS alerts where backslashes / quotes are mangled.
        // Append captured stderr (the parser-internal detail from
        // llama-grammar.cpp:713) wrapped in sentinel markers so unrelated
        // process-level stderr writes during the capture window are
        // visually attributable rather than mistaken for grammar errors.
        // Filter:  subsystem:com.pastura category:LlamaCppService
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
          description: "GBNF grammar parse failed: \(snippet)")
      }
      llama_sampler_chain_add(chain, grammarSampler)
    }

    llama_sampler_chain_add(chain, llama_sampler_init_temp(Self.temperature))
    llama_sampler_chain_add(
      chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

    return chain
  }

  /// Call `llama_sampler_init_grammar` with stderr redirected to a `Pipe`
  /// so the parser-internal error message is captured for diagnostics.
  ///
  /// **Why dup2 is needed.** llama.cpp's grammar parser writes detailed
  /// errors via `fprintf(stderr, "error parsing grammar: %s\n\n%s\n", ...)`
  /// at `llama-grammar.cpp:713` (b8694), then `parser.parse` returns false.
  /// Only the outer `LLAMA_LOG_ERROR("failed to parse grammar")` at line
  /// 1209 reaches our `llama_log_set` callback (`LlamaCppService.swift`).
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
  ///   `capturedStderr` is the (possibly empty / lossy-UTF-8-decoded)
  ///   stderr payload from the call window, or a
  ///   `"<stderr capture skipped: …>"` sentinel when redirect setup
  ///   failed.
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
    dup2(savedStderr, STDERR_FILENO)
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
