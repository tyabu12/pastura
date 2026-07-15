import Foundation
import LlamaSwift
import os

// MARK: - DRY anti-repetition sampler (#1105)

/// DRY-sampler tuning for the #1105 anti-repetition A/B, read from the
/// environment so a single build can run both arms (base = unset, arm =
/// `PASTURA_DRY_MULTIPLIER` set). The LLM layer cannot import
/// `App/FeatureFlags` (dependency rule), and env vars are unreachable in
/// TestFlight/Release — so this is a **harness-only A/B lever**, NOT the
/// shipped control. On a Go, relocate the toggle to a Models-layer tunable /
/// `ModelDescriptor` field / unconditional-with-tuned-constants. Precedent
/// for env-driven LLM-layer config: `PASTURA_TRACE_LLM`
/// (`LlamaCppService+Trace.swift`).
nonisolated struct DryConfig {
  let multiplier: Float
  let base: Float
  let allowedLength: Int32
  let penaltyLastN: Int32
  /// Sequence-breaker tokens that reset DRY's n-gram match. A newline breaker
  /// keeps a repeated *line* from being treated as one long span; combined
  /// with content-only seeding (no JSON scaffold) it is a sufficient default
  /// for statement-value text.
  let seqBreakers: [String]

  /// Parse the env toggle, or `nil` when disabled (multiplier ≤ 0 / unset).
  /// Defaults follow the webui/koboldcpp DRY lineage, with `allowedLength`
  /// nudged to 3 because ja names / topic words tokenize to 2–3 tokens.
  static func fromEnvironment() -> DryConfig? {
    let env = ProcessInfo.processInfo.environment
    func float(_ key: String, _ fallback: Float) -> Float {
      env[key].flatMap(Float.init) ?? fallback
    }
    func int32(_ key: String, _ fallback: Int32) -> Int32 {
      env[key].flatMap(Int32.init) ?? fallback
    }
    let multiplier = float("PASTURA_DRY_MULTIPLIER", 0.0)
    guard multiplier > 0 else { return nil }
    return DryConfig(
      multiplier: multiplier,
      base: float("PASTURA_DRY_BASE", 1.75),
      allowedLength: int32("PASTURA_DRY_ALLOWED_LENGTH", 3),
      penaltyLastN: int32("PASTURA_DRY_LAST_N", 512),
      seqBreakers: ["\n"])
  }
}

nonisolated extension LlamaCppService {
  /// Build a DRY sampler (`llama_sampler_init_dry`) seeded content-only with
  /// `seeds`, or `nil` when disabled. Non-throwing: DRY is an optional quality
  /// enhancement, so any missing precondition (env toggle off, no seeds, no
  /// model, NULL sampler) degrades to `nil` rather than failing the whole
  /// generation. Ownership: the returned handle is caller-owned (freed in the
  /// run-loop `defer`s alongside `grammar`).
  ///
  /// **Content-only seeding**: `seeds` are the prior statement's *value* text,
  /// tokenized with `addSpecial: false` and fed to the DRY handle via
  /// `llama_sampler_accept`. JSON scaffold tokens (`{`, `"statement"`, `}`)
  /// are absent from the seed, so DRY cannot form a match against them and
  /// cannot fight the grammar at structural positions. Fidelity caveat:
  /// retokenizing isolated value text may not byte-match the token boundaries
  /// the model emitted inside a JSON string context, so the penalty can be
  /// slightly weaker than an exact-token seed — a favourable asymmetry
  /// (under-penalizes, so a positive A/B result is trustworthy; a null result
  /// does not cleanly rule DRY out). The seeded-token count is logged so the
  /// #1105 probe can quantify this before a No-Go.
  func buildAndSeedDrySampler(
    vocab: OpaquePointer, model: OpaquePointer?, seeds: [String]
  ) -> UnsafeMutablePointer<llama_sampler>? {
    guard let config = DryConfig.fromEnvironment(), !seeds.isEmpty, let model
    else { return nil }

    let dry = withArrayOfCStrings(config.seqBreakers) { breakerPtrs in
      llama_sampler_init_dry(
        vocab, llama_model_n_ctx_train(model), config.multiplier, config.base,
        config.allowedLength, config.penaltyLastN,
        breakerPtrs.baseAddress, breakerPtrs.count)
    }
    guard let dry else {
      logger.warning("DRY sampler init returned NULL — proceeding without it (#1105)")
      return nil
    }

    // Seed content-only. `llama_sampler_accept` on a DRY sampler is a
    // ring-buffer push (no grammar member → no #253 crash risk); safe for
    // any token, so no EOG/catch handling is needed here.
    var seededTokenCount = 0
    for seed in seeds {
      guard let tokens = try? tokenize(vocab: vocab, text: seed, addSpecial: false) else {
        continue
      }
      for token in tokens {
        llama_sampler_accept(dry, token)
        seededTokenCount += 1
      }
    }
    logger.debug(
      """
      DRY seeded (#1105): \(seededTokenCount, privacy: .public) tokens from \
      \(seeds.count, privacy: .public) seed(s) — mult=\(config.multiplier, privacy: .public) \
      base=\(config.base, privacy: .public) allowed=\(config.allowedLength, privacy: .public) \
      lastN=\(config.penaltyLastN, privacy: .public)
      """)
    // Probe instrumentation (#1105): os_log `.debug` does not surface to a
    // macOS CLI tool's stderr, so mirror the seeding fact to stderr where the
    // harness `.log` captures it — this is how the A/B verifies DRY actually
    // fired and quantifies seed-token fidelity. Only reached when DRY is
    // enabled (env-gated), so production (env unset) never writes here. On a
    // Go this becomes a proper os_log-only diagnostic.
    FileHandle.standardError.write(
      Data(
        ("[#1105 DRY] seeded \(seededTokenCount) tok / \(seeds.count) seed(s) "
          + "mult=\(config.multiplier) allowed=\(config.allowedLength) "
          + "lastN=\(config.penaltyLastN)\n").utf8))
    return dry
  }

  /// Call `body` with a C `const char **` view of `strings`, valid only for
  /// the closure's duration. Nested `withCString` scopes keep every pointer
  /// alive across the call; `llama_sampler_init_dry` deep-copies its
  /// `seq_breakers`, so the pointers need to outlive only the init call.
  /// Recursion depth == `strings.count` (a handful of breakers), so the
  /// stack cost is negligible.
  func withArrayOfCStrings<R>(
    _ strings: [String],
    _ body: (UnsafeMutableBufferPointer<UnsafePointer<CChar>?>) -> R
  ) -> R {
    func loop(_ index: Int, _ pointers: [UnsafePointer<CChar>?]) -> R {
      guard index < strings.count else {
        // `llama_sampler_init_dry` imports `const char **` as a MUTABLE outer
        // pointer (the `const` binds `char`, not the array), so a mutable
        // buffer is required even though the callee only reads it.
        var mutablePointers = pointers
        return mutablePointers.withUnsafeMutableBufferPointer { body($0) }
      }
      return strings[index].withCString { cStr in
        loop(index + 1, pointers + [cStr])
      }
    }
    return loop(0, [])
  }
}
