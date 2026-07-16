import Foundation
import LlamaSwift
import os

// MARK: - DRY anti-repetition sampler (#1105)

/// DRY-sampler tuning for #1105 anti-repetition. Ships **unconditional** with
/// the tuned constants below — DRY is on by default in every build. The
/// environment is now an optional **A/B override lever**: it is unreachable in
/// TestFlight/Release (env vars aren't set there), so it never affects
/// production, but it lets the ADR-013 harness sweep alternative constants or
/// run the base arm — `PASTURA_DRY_MULTIPLIER=0` disables DRY. This keeps the
/// config in the LLM layer where it belongs (a llama.cpp sampler knob, not a
/// backend-agnostic domain model — Models/ would be the wrong home; the LLM
/// layer also can't import `App/FeatureFlags` per the dependency rule).
/// Precedent for env-driven LLM-layer config: `PASTURA_TRACE_LLM`
/// (`LlamaCppService+Trace.swift`).
///
/// **ja/en divergence (#1105 word_wolf mult sweep, Gemma 4 E2B Q4).** DRY
/// substantially cuts self-echo in ja (char-3gram self-echo 0.34→0.20 at
/// `mult=0.8`, verbatim echoes eliminated) but is weaker in en: exact echoes
/// still go to zero, yet char-3gram self-echo stays ~flat. Two things are
/// **measured**: it is not a seeding gap (see `buildAndSeedDrySampler`), and the
/// wiring fires — observed penalties land exactly on
/// `multiplier * base^(L - allowedLength)`. Why en differs is **indicative
/// only**: the ramp opens at `multiplier`, needs ~5 matched tokens to bite, and
/// resets on each forced divergence — so ja diverts early (max penalty 4.3)
/// where en runs long before it bites (23.0). One word_wolf run per locale, and
/// en's decisive behaviour rests on 4 positions — re-measure before tuning the
/// ramp. Stage-0 record: #1133. en is not the launch-critical locale (English
/// App Store is a Phase 2→3 gate) and DRY is regression-free there, so this
/// ships as-is.
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

  /// Shipped default multiplier. The #1105 word_wolf sweep (3 runs/arm) showed
  /// a monotonic dose curve — 0.5 under-penalizes (self-echo 0.29), 1.1
  /// over-tightens for marginal gain (0.16); 0.8 sits at a coherent,
  /// non-aggressive point (0.20) that eliminates verbatim echoes without
  /// forcing paraphrase collapse, and generalizes more safely across untested
  /// scenarios/models than the aggressive edge. Values follow the
  /// webui/koboldcpp DRY lineage.
  static let defaultMultiplier: Float = 0.8

  /// Resolve the production config from the process environment. Thin wrapper
  /// over ``resolve(environment:)`` so the pure resolution logic is unit-testable
  /// without mutating `setenv` (which is process-global and races parallel tests).
  static func resolve() -> DryConfig? {
    resolve(environment: ProcessInfo.processInfo.environment)
  }

  /// Pure resolution over an injected environment dict, applying any harness
  /// A/B overrides on top of the shipped constants. Returns `nil` only for the
  /// explicit base arm (`PASTURA_DRY_MULTIPLIER=0`, or any non-positive
  /// override); otherwise DRY is enabled. `allowedLength` is 3 because ja names
  /// / topic words tokenize to 2–3 tokens.
  static func resolve(environment env: [String: String]) -> DryConfig? {
    func float(_ key: String, _ fallback: Float) -> Float {
      env[key].flatMap(Float.init) ?? fallback
    }
    func int32(_ key: String, _ fallback: Int32) -> Int32 {
      env[key].flatMap(Int32.init) ?? fallback
    }
    let multiplier = float("PASTURA_DRY_MULTIPLIER", defaultMultiplier)
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
  /// enhancement, so any missing precondition (the explicit base arm
  /// `PASTURA_DRY_MULTIPLIER=0`, no seeds, no
  /// model, NULL sampler) degrades to `nil` rather than failing the whole
  /// generation. Ownership: the returned handle is caller-owned (freed in the
  /// run-loop `defer`s alongside `grammar`).
  ///
  /// **Content-only seeding**: `seeds` are the prior statement's *value* text,
  /// tokenized with `addSpecial: false` and fed to the DRY handle via
  /// `llama_sampler_accept`. JSON scaffold tokens (`{`, `"statement"`, `}`)
  /// are absent from the seed, so DRY cannot form a match against them and
  /// cannot fight the grammar at structural positions. Retokenization fidelity
  /// is **measured, not assumed** (#1133): the re-tokenized seed reproduces the
  /// tokens the model actually emitted to within 1 token in en (uniformly, 10/10
  /// seeded turns) and 3 in ja, leaving contiguous runs of 12–38 tokens ≫
  /// `allowedLength`. The en uniformity is consistent with a single systematic
  /// difference on the seed's leading token (SentencePiece's dummy prefix —
  /// `▁I` vs `I`). So the boundary drift does not gate DRY, is not larger in en,
  /// and does not explain the weaker en effect (see `DryConfig`) — an
  /// exact-token seed would recover a token or three, not a mechanism.
  func buildAndSeedDrySampler(
    vocab: OpaquePointer, model: OpaquePointer?, seeds: [String]
  ) -> UnsafeMutablePointer<llama_sampler>? {
    guard let config = DryConfig.resolve(), !seeds.isEmpty, let model
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
    if seededTokenCount == 0 {
      // Reached with a non-empty `seeds` (guarded above) yet nothing seeded —
      // every seed failed to tokenize. The handle stays valid but degrades to
      // a within-generation-only penalty, silently defeating the cross-turn
      // purpose of #1105, so surface it above `.debug`.
      logger.warning(
        """
        DRY seeded 0 tokens from \(seeds.count, privacy: .public) non-empty \
        seed(s) (#1105) — all tokenized empty; cross-turn penalty inert this turn
        """)
    }
    logger.debug(
      """
      DRY seeded (#1105): \(seededTokenCount, privacy: .public) tokens from \
      \(seeds.count, privacy: .public) seed(s) — mult=\(config.multiplier, privacy: .public) \
      base=\(config.base, privacy: .public) allowed=\(config.allowedLength, privacy: .public) \
      lastN=\(config.penaltyLastN, privacy: .public)
      """)
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
