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

/// Why a generation ran without a DRY sampler (#1483).
///
/// Each case maps to exactly one exit path, and together with
/// `samplerDrySeeded` they cover every **non-throwing** way `createSampler`
/// can finish — so a harness run that emits **no** `samplerDry*` line at all
/// means the sampler path was never reached, which is a different fact from
/// "DRY was off". A single "DRY unavailable" marker could not make that
/// distinction.
///
/// **Not covered: the three throwing exits** (`chain_init` NULL, grammar
/// without vocab, `init_grammar` NULL — the #194 path). Those leave no marker,
/// so a marker counts *generations that reached sampler construction*, never
/// *generations attempted*. `prepareGeneration` can also throw upstream of
/// `createSampler`. A short count is therefore a real signal, not necessarily
/// a broken instrument — read `run_end.status` alongside the sweep.
///
/// The raw values are the join key for the `.stderr.log` sweep in
/// `.claude/skills/model-eval/SKILL.md` § Step 2, whose expectations are
/// written per reason; `DrySamplerConfigTests` pins the set so a rename or a
/// sixth non-throwing path cannot land without updating both.
nonisolated enum DryUnavailableReason: String, CaseIterable, Sendable {
  /// `DryConfig.resolve()` returned nil — the harness A/B base arm
  /// (`PASTURA_DRY_MULTIPLIER=0`). Never reached in TestFlight / Release.
  case disabled
  /// The caller passed no prior text. Structural, not a fault: `speak_each`
  /// is the only seeding phase in Engine, and it seeds nothing in round 1.
  case noSeeds = "no-seeds"
  /// No model pointer, so `n_ctx_train` is unreadable.
  case noModel = "no-model"
  /// `llama_sampler_init_dry` returned NULL.
  case nullInit = "null-init"
  /// `createSampler` returned before reaching the builder at all — no
  /// grammar (`schema == nil`), so DRY is gated off upstream.
  case noGrammar = "no-grammar"
}

nonisolated extension LlamaCppService {
  /// The line emitted once per generation that installs a DRY sampler.
  ///
  /// `nCtxTrain` is on the line deliberately: llama.cpp b10327 **drops** that
  /// argument from `llama_sampler_init_dry`, so recording what the pinned
  /// b8694 build passes is what makes a harness run a baseline the bump can
  /// be diffed against, rather than a mere liveness check (#1415).
  ///
  /// Pure and `static` so the format is unit-testable without inference — the
  /// seeding path itself needs a real model (PR #463).
  static func drySeededLine(
    seededTokenCount: Int, seedCount: Int, nCtxTrain: Int32,
    config: DryConfig, model: String
  ) -> String {
    "samplerDrySeeded seededTokens=\(seededTokenCount) seeds=\(seedCount) "
      + "nCtxTrain=\(nCtxTrain) mult=\(config.multiplier) base=\(config.base) "
      + "allowed=\(config.allowedLength) lastN=\(config.penaltyLastN) model=\(model)"
  }

  /// The line emitted once per generation that runs without a DRY sampler.
  static func dryUnavailableLine(reason: DryUnavailableReason, model: String) -> String {
    "samplerDryUnavailable reason=\(reason.rawValue) model=\(model)"
  }

  /// Emit one diagnostic line to OSLog **and** to stderr.
  ///
  /// The stderr mirror is the only channel the ADR-013 harness can read: it
  /// captures stderr to a `.stderr.log` sidecar, and does not retain `.debug`
  /// OSLog records at all — which is why the pre-#1483 `.debug` success line
  /// was invisible to it, and why #1415's spike had to record this call path
  /// as behaviourally unverified. (That spike is also where the window was
  /// measured; nothing in this repo reads OSLog, so it is not re-derivable
  /// here.) The LLM layer cannot use the harness's `EngineLogger` seam
  /// instead: that protocol lives in `Engine/`, and `LLM/` must not depend
  /// on it.
  ///
  /// `anomalous` keeps the pre-#1483 OSLog severity on the two paths that had
  /// it (NULL init, zero tokens seeded) without splitting the stderr channel.
  /// Interpolated `.public` because the line carries only model metadata and
  /// numbers — never seeds, which are agent output (CLAUDE.md Logger privacy).
  func emitDryDiagnostic(_ line: String, anomalous: Bool = false) {
    if anomalous {
      logger.warning("\(line, privacy: .public)")
    } else {
      logger.debug("\(line, privacy: .public)")
    }
    // Same rationale as `emitGrammarResampleDiagnostic`'s mirror: CLI os.Logger
    // output is not reliably queryable via `log show`. Invisible on iOS.
    // Volume profile differs from that sibling, though — do not carry its
    // "rare path" framing across: this fires once per generation, not once per
    // event. ~120 B against seconds of inference, so still negligible.
    fputs(line + "\n", stderr)
  }

  /// Emit the unavailable marker for `reason`. Wrapped so each `guard` in
  /// ``buildAndSeedDrySampler(vocab:model:seeds:)`` stays one statement rather
  /// than a two-line emit repeated at every exit.
  func emitDryUnavailable(_ reason: DryUnavailableReason) {
    emitDryDiagnostic(
      Self.dryUnavailableLine(reason: reason, model: modelIdentifier),
      anomalous: reason == .nullInit)
  }

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
    // Split into one guard per precondition (#1483): the merged form could
    // only report "no DRY", and the three causes want different readings —
    // `disabled` is the harness base arm, `no-seeds` is structural for every
    // phase but `speak_each`, `no-model` would be a wiring bug.
    guard let config = DryConfig.resolve() else {
      emitDryUnavailable(.disabled)
      return nil
    }
    guard !seeds.isEmpty else {
      emitDryUnavailable(.noSeeds)
      return nil
    }
    guard let model else {
      emitDryUnavailable(.noModel)
      return nil
    }

    let nCtxTrain = llama_model_n_ctx_train(model)
    let dry = withArrayOfCStrings(config.seqBreakers) { breakerPtrs in
      llama_sampler_init_dry(
        vocab, nCtxTrain, config.multiplier, config.base,
        config.allowedLength, config.penaltyLastN,
        breakerPtrs.baseAddress, breakerPtrs.count)
    }
    guard let dry else {
      emitDryUnavailable(.nullInit)
      return nil
    }

    let seededTokenCount = seedTokens(into: dry, vocab: vocab, seeds: seeds)
    // `seededTokenCount == 0` is reached with a non-empty `seeds` (guarded
    // above) yet nothing seeded — every seed failed to tokenize. The handle
    // stays valid but degrades to a within-generation-only penalty, silently
    // defeating the cross-turn purpose of #1105, so raise the OSLog severity.
    emitDryDiagnostic(
      Self.drySeededLine(
        seededTokenCount: seededTokenCount, seedCount: seeds.count,
        nCtxTrain: nCtxTrain, config: config, model: modelIdentifier),
      anomalous: seededTokenCount == 0)
    return dry
  }

  /// Feed `seeds` to `dry` content-only and return the token count actually
  /// accepted. Extracted from ``buildAndSeedDrySampler(vocab:model:seeds:)``
  /// so that function reads as its guard ladder plus one seeding call.
  ///
  /// `llama_sampler_accept` on a DRY sampler is a ring-buffer push (no grammar
  /// member → no #253 crash risk); safe for any token, so no EOG/catch
  /// handling is needed here.
  private func seedTokens(
    into dry: UnsafeMutablePointer<llama_sampler>, vocab: OpaquePointer, seeds: [String]
  ) -> Int {
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
    return seededTokenCount
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
