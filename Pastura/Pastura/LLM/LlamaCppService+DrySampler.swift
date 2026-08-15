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
/// One case per exit path; with `samplerDrySeeded` they cover every
/// **non-throwing** exit of `createSampler`. So a run emitting **no**
/// `samplerDry*` line means the sampler path was never reached — a different
/// fact from "DRY was off".
///
/// **The two throwing exits carry no marker** (`chain_init` NULL,
/// `init_grammar` NULL — #194); `prepareGeneration` can throw upstream too.
/// The former third exit — grammar supplied without vocab — became
/// unrepresentable when the b10327 pin made `createSampler`'s `vocab`
/// non-optional. A marker counts generations that *reached sampler
/// construction*, never *attempted*, so read `run_end.status` alongside the
/// sweep before calling a short count a broken instrument.
///
/// Raw values join to the `.stderr.log` sweep in `/model-eval` § Step 2;
/// `DrySamplerConfigTests` pins the set.
nonisolated enum DryUnavailableReason: String, CaseIterable, Sendable {
  /// `DryConfig.resolve()` returned nil — the harness A/B base arm
  /// (`PASTURA_DRY_MULTIPLIER=0`). Never reached in TestFlight / Release.
  case disabled
  /// The caller passed no prior text. Structural, not a fault: `speak_each` is
  /// the only seeding phase in Engine, and it seeds an agent once that agent
  /// has a non-empty prior `lastOutputs` entry — **not** "round 2 onward",
  /// since `lastOutputs` persists across phases, so a *second* `speak_each`
  /// seeds from its first round. Per-scenario counts:
  /// `docs/models/eval-log.md` § "DRY sampler construction".
  case noSeeds = "no-seeds"
  /// `llama_sampler_init_dry` returned NULL.
  case nullInit = "null-init"
  /// `createSampler` returned before reaching the builder at all — no
  /// grammar (`schema == nil`), so DRY is gated off upstream.
  case noGrammar = "no-grammar"
}

nonisolated extension LlamaCppService {
  /// The line emitted once per generation that installs a DRY sampler.
  ///
  /// Every field is a `DryConfig` value the sampler was built from, plus the
  /// seeding outcome. `nCtxTrain` was here until the b10327 pin, which dropped
  /// `n_ctx_train` from `llama_sampler_init_dry` — a field naming an argument
  /// the sampler no longer takes reads as a live parameter and is worse than
  /// no field at all.
  ///
  /// Pure and `static` so the format is unit-testable without inference — the
  /// seeding path itself needs a real model (PR #463).
  static func drySeededLine(
    seededTokenCount: Int, seedCount: Int,
    config: DryConfig, model: String
  ) -> String {
    "samplerDrySeeded seededTokens=\(seededTokenCount) seeds=\(seedCount) "
      + "mult=\(config.multiplier) base=\(config.base) "
      + "allowed=\(config.allowedLength) lastN=\(config.penaltyLastN) model=\(model)"
  }

  /// The line emitted once per generation that runs without a DRY sampler.
  static func dryUnavailableLine(reason: DryUnavailableReason, model: String) -> String {
    "samplerDryUnavailable reason=\(reason.rawValue) model=\(model)"
  }

  /// Emit one diagnostic line to OSLog **and** to stderr.
  ///
  /// The stderr mirror is the only channel the ADR-013 harness can read: it
  /// captures stderr to a `.stderr.log` sidecar and retains no `.debug` OSLog
  /// records at all (measured in #1415; nothing in this repo reads OSLog, so it
  /// is not re-derivable here). `LLM/` cannot use the harness's `EngineLogger`
  /// seam instead — that protocol lives in `Engine/`, and the dependency rule
  /// forbids the import.
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

  /// Emit the unavailable marker for `reason`. `.nullInit` is the only one that
  /// raises OSLog severity — the rest are expected states, not faults.
  func emitDryUnavailable(_ reason: DryUnavailableReason) {
    emitDryDiagnostic(
      Self.dryUnavailableLine(reason: reason, model: modelIdentifier),
      anomalous: reason == .nullInit)
  }

  /// Build a DRY sampler (`llama_sampler_init_dry`) seeded content-only with
  /// `seeds`, or `nil` when disabled. Non-throwing: DRY is an optional quality
  /// enhancement, so any missing precondition (the explicit base arm
  /// `PASTURA_DRY_MULTIPLIER=0`, no seeds, NULL sampler) degrades to `nil`
  /// rather than failing the whole
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
    vocab: OpaquePointer, seeds: [String]
  ) -> UnsafeMutablePointer<llama_sampler>? {
    // One guard per precondition, and do not re-merge them: each exit needs its
    // own marker, or two distinguishable states collapse into "no DRY". The
    // readings are on `DryUnavailableReason`'s cases.
    guard let config = DryConfig.resolve() else {
      emitDryUnavailable(.disabled)
      return nil
    }
    guard !seeds.isEmpty else {
      emitDryUnavailable(.noSeeds)
      return nil
    }

    let dry = withArrayOfCStrings(config.seqBreakers) { breakerPtrs in
      llama_sampler_init_dry(
        vocab, config.multiplier, config.base,
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
        config: config, model: modelIdentifier),
      anomalous: seededTokenCount == 0)
    return dry
  }

  /// Feed `seeds` to `dry` content-only and return the token count actually
  /// accepted.
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
