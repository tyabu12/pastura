import Foundation

/// Force-constructs a URL from a string literal. Fatal error if the literal is malformed.
/// Acceptable because the input is a compile-time constant that we control — NOT user input.
nonisolated private func unsafeURL(_ string: String) -> URL {
  guard let url = URL(string: string) else {
    preconditionFailure("Malformed URL literal: \(string)")
  }
  return url
}

/// Static catalog of on-device LLM models shipped with Pastura.
///
/// Entries are constructed at compile time from known-good HuggingFace metadata
/// (pinned commit SHA, file size, SHA-256). This keeps model downloads
/// deterministic across app versions and users — see ROADMAP Phase 2 TD
/// "Remote model manifest" (originally #82) for the deferred dynamic-fetch
/// alternative.
///
/// `ModelManager` consumes this catalog to resolve per-model file paths,
/// download URLs, and integrity checks. `LlamaCppService` consumes individual
/// descriptors for prompt-format hints (`stopSequence`, `systemPromptSuffix`).
///
/// ### Model-update (supersede) convention
///
/// One of **two** shapes for replacing a build; § "ADD-and-keep" below is the
/// other, and the boundary between them is stated there. This one is the
/// default — reach for ADD-and-keep only when the criteria there are met.
///
/// A `ModelDescriptor` is immutable and there is no `version` field, so
/// *updating* a model means shipping a new entry here with a new `id` AND a
/// new `fileName`, and removing the old entry. (In-place updates without an
/// app release are the job of the deferred "Remote model manifest" — see
/// ROADMAP "Technical Debt to Address".)
///
/// **When you remove an entry, move its `id` into `RETIRED_MODEL_IDS` in
/// `scripts/gallery_highlight_validate.py` in the same PR.** Shipped gallery
/// highlights pin the model they were generated on as a statement about the
/// past (ADR-029 Decision 1), and the gate checks that string against this
/// catalog — so removing an id here turns every highlight naming it red, on a
/// PR that has nothing to do with the gallery.
///
/// The superseded GGUF stays on disk. Because `ModelManager.checkModelStatus`
/// only iterates the *live* catalog, that file becomes an orphan with no
/// per-model row. `ModelManager.orphanedModelFiles()` detects it and Settings
/// → Models surfaces it as an "Unused model file" row for manual deletion —
/// it is never silent-auto-deleted (consistent with ADR-015's
/// no-silent-auto-delete posture). See #548.
///
/// ### ADD-and-keep
///
/// The shape adopted for `gemma4E2BQAT` (#1487, ADR-002 § Amendment 2026-08-15
/// — ADD-and-keep; that ADR carries a second amendment of the same date, for
/// the pin bump).
/// The new entry joins `catalog` and the old one **stays**, carrying
/// ``ModelDescriptor/replacesModelID`` to name what it takes over from.
/// `ModelManager.visibleCatalog` then hides the replaced entry from the
/// user-facing lists once it is **both** absent from disk **and** not the active
/// model, so a new install never sees it while an existing user keeps their
/// downloaded build, their row, and a way back if the newer one misbehaves on
/// their device. That second conjunct is load-bearing rather than defensive —
/// see `visibleCatalog`'s own doc for the active-but-corrupted case it covers.
///
/// **Use it when the replacement is the same model** — a requantisation, a
/// re-export, a QAT rebuild — where the supersede convention's forced
/// re-download buys the user nothing but a second multi-GB transfer and an
/// orphaned file. Use the supersede convention above for a genuinely different
/// model, where keeping the old entry would just be catalog clutter.
///
/// **The replaced entry is not removed, so nothing here retires.** What is
/// load-bearing is its **membership of `catalog`**. The three sharpest
/// consumers — not an exhaustive list — reach it by membership rather than
/// through `lookup(id:)`, so grepping that name will not find them:
///
/// - `ModelManager.activeDescriptor` is `catalog.first(where:)`, so a user still
///   running the old build would lose their active model.
/// - `orphanedModelFiles()` derives from `catalog.map(\.fileName)`, so dropping
///   the entry would surface that user's **in-use** GGUF as a deletable "Unused
///   model file".
/// - `GallerySeedYAMLTests.recommendedModelMatchesRegistry` validates every
///   `gallery.json` `recommended_model` against `catalog.map(\.id)`, and the
///   whole shipped feed still names the replaced build.
///
/// Display-name resolution is a fourth, milder one, and it degrades two
/// different ways. The ``lookup(id:)`` callsites fall back to the **raw id**, so
/// the gallery would print `gemma-4-e2b-q4-k-m` where "Gemma 4 E2B" belongs.
/// ``shortDisplayName(forIdentifier:)`` matches on `displayName` rather than
/// `id`, so it never reaches the raw id — it falls through to the persisted
/// long label, and the past-results share card silently loses its short name.
/// Both land on exactly the user this shape exists to protect.
///
/// `RETIRED_MODEL_IDS` above is **not** a dependency at all — it is the reason
/// nothing has to retire, since it applies only when an id actually *leaves*.
enum ModelRegistry {
  nonisolated static let gemma4E2B: ModelDescriptor = ModelDescriptor(
    id: "gemma-4-e2b-q4-k-m",
    displayName: "Gemma 4 E2B (Q4_K_M)",
    shortDisplayName: "Gemma 4 E2B",
    vendor: "Google",
    vendorURL: unsafeURL("https://deepmind.google"),
    downloadURL: unsafeURL(
      "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/f064409f340b34190993560b2168133e5dbae558/gemma-4-E2B-it-Q4_K_M.gguf"
    ),
    fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
    fileSize: 3_106_735_776,
    sha256: "ac0069ebccd39925d836f24a88c0f0c858d20578c29b21ab7cedce66ee576845",
    // Carries no Gemma marker, deliberately: `<|im_end|>` is a ChatML sentinel
    // absent from this model's vocabulary, so this generation-side path is
    // inert here — which is what lets a spelled-out `<turn|>` reach the parser,
    // keyed on the `turnMarkers` below. Repointing it would activate a behaviour
    // on an assumption; deferred to #1451, which must change every site
    // (`grep -rn '#1451'`) (#1417). Canonical note: `LlamaCppService.stopSequence`.
    stopSequence: "<|im_end|>",
    // Measured from the GGUF header of the exact file pinned above: `<|turn>`
    // id 105 / `<turn|>` id 106, both `token_type=3` (CONTROL), `eos = 106`,
    // vocab 262,144. Header-read step: `docs/models/onboarding.md`
    // § "Stage 0 — Harness profile". The claim that neither ChatML string
    // occurs in that vocabulary is not re-derivable from these ids — it's
    // carried as an assertion on `LlamaCppService.stopSequence`, and is
    // distinct from Stage 0's transcript marker sweep.
    turnMarkers: ChatTurnMarkers(start: "<|turn>", end: "<turn|>"),
    minRAM: 6_500_000_000,
    modelInfoURL: unsafeURL("https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF"),
    systemPromptSuffix: nil,
    // Carries the "same Gemma, older and larger" disambiguation, because this is the row
    // that can appear beside its replacement (`visibleCatalog`) — the reader who needs it.
    tagline: String(localized: "The older, larger build of the same Gemma.")
  )

  nonisolated static let qwen34B: ModelDescriptor = ModelDescriptor(
    id: "qwen-3-4b-q4-k-m",
    displayName: "Qwen 3 4B (Q4_K_M)",
    shortDisplayName: "Qwen 3 4B",
    vendor: "Alibaba",
    vendorURL: unsafeURL("https://qwenlm.github.io"),
    downloadURL: unsafeURL(
      "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf"
    ),
    fileName: "Qwen3-4B-Q4_K_M.gguf",
    fileSize: 2_497_280_256,
    sha256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
    stopSequence: "<|im_end|>",
    // Qwen 3 genuinely is ChatML: `<|im_start|>` 151644 / `<|im_end|>` 151645,
    // both CONTROL, `eos = 151645`. Header-read: `docs/models/onboarding.md`
    // § "Stage 0 — Harness profile".
    turnMarkers: .chatML,
    minRAM: 6_500_000_000,
    modelInfoURL: unsafeURL("https://huggingface.co/Qwen/Qwen3-4B-GGUF"),
    systemPromptSuffix: "/no_think",
    // Prefill the assistant turn with the empty-thinking marker so Qwen 3
    // bypasses thinking mode entirely. Issue #366 — without this, Qwen
    // emits `<think>` (token 151667) as its first sampled token and the
    // GBNF grammar sampler crashes on `accept_token` (uncaught C++ exception).
    // The `/no_think` system suffix above is a soft training hint that does
    // not prevent the leading `<think>` token; the prefill is the load-bearing
    // fix. `/no_think` stays as belt-and-suspenders.
    assistantPrefix: "<think>\n\n</think>\n\n",
    // Tagline avoids any "reasoning"/"thinking" framing on purpose: this model
    // runs with `/no_think` + the empty-thinking prefill above, so thinking
    // mode is OFF. Copy that implied a reasoning mode would contradict the
    // runtime config. It states no character claim and no vendor/size either — the ledger has no
    // Qwen *candidate* entry (only a one-sentence aside inside another's, n=1), and `ModelRow` shows both as meta.
    tagline: String(localized: "A different model family from Gemma. Try it for a different feel.")
  )

  /// Gemma 4 E2B, quantization-aware-trained rebuild.
  ///
  /// **Needs the llama.swift `2.10327.0` / llama.cpp b10327 pin or newer.** The
  /// Gemma 4 QAT exports ship a shared-KV tail layer that earlier builds refuse
  /// with `missing tensor 'blk.15.attn_k.weight'` (`.claude/rules/engine.md`
  /// § "GGUF source *and variant* matter"). Nothing couples the two in code and
  /// the failure lands *after* a 2.62 GB download rather than at build time — so
  /// a pin downgrade has to drop this entry with it.
  ///
  /// `minRAM` is inherited from `gemma4E2B` and **stays** unmeasured. The file is
  /// 0.49 GB smaller, but the floor gates *runtime* footprint, and none of
  /// ADR-011 P3–P5 measures that — P3 is a crash-free GBNF PoC, P4 a same-session
  /// no-regression run against the incumbents, P5 a static sampler-API check. So
  /// their PASS does not license lowering it; inheriting stays the conservative
  /// side of an unknown that only a 6 GB-tier measurement can settle.
  nonisolated static let gemma4E2BQAT: ModelDescriptor = ModelDescriptor(
    id: "gemma-4-e2b-qat-q4-k-xl",
    displayName: "Gemma 4 E2B (QAT)",
    // Not named after the upstream `UD-Q4_K_XL` filename on purpose: the file is
    // not a K-quant. Its tensor spread is `Q4_0`×278 / `F32`×263 and
    // `general.name` reads "smart Q4_0, QAT-lossless", so a `Q4_K_XL` label in
    // the picker would state a quantisation format the file does not use.
    shortDisplayName: "Gemma 4 E2B QAT",
    vendor: "Google",
    vendorURL: unsafeURL("https://deepmind.google"),
    downloadURL: unsafeURL(
      "https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF/resolve/66a399f68ddd113b06dff02fca9523e55465d11d/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf"
    ),
    fileName: "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf",
    fileSize: 2_620_370_976,
    sha256: "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889",
    // Same deliberate divergence as `gemma4E2B`, inert for the same reason — but
    // that reason is a property of the *export*, not of the model, so it was
    // re-measured against this file rather than carried across (a wrong pair
    // fails silently, `docs/models/onboarding.md` § "Stage 0 — Harness profile
    // (new model family only)" — optional here, run anyway): `<|im_end|>` is
    // absent from this vocabulary too. Deferred to #1451, which must change
    // every site (`grep -rn '#1451'`). Canonical note:
    // `LlamaCppService.stopSequence`.
    stopSequence: "<|im_end|>",
    // Measured from the GGUF header of the exact file pinned above: `<|turn>`
    // id 105 / `<turn|>` id 106, both `token_type=3` (CONTROL), vocab 262,144,
    // 541 tensors. `<turn|>` is `eot_token_id` here, and `eos_token_id` is 1
    // (`<eos>`) — where `gemma4E2B` carries `<turn|>` as its `eos`. Termination
    // is unaffected because `llama_vocab_is_eog` covers both fields, but do not
    // copy either descriptor's eos/eot claim onto the other.
    turnMarkers: ChatTurnMarkers(start: "<|turn>", end: "<turn|>"),
    minRAM: 6_500_000_000,
    modelInfoURL: unsafeURL("https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF"),
    // No assistant prefill. `.claude/rules/engine.md` § "Grammar sampler does
    // not mask special tokens" makes this a per-model check, and this export's
    // chat template differs textually from `gemma4E2B`'s — so the shared base
    // model does not settle it. Gate 1 running crash-free on this file does.
    systemPromptSuffix: nil,
    // No size comparison — this is the replacement, so a fresh install has no referent on
    // screen; that line lives on `gemma4E2B` (`ModelDescriptor.tagline`). Character claims
    // are n=1: `docs/models/eval-log.md` § "Gemma 4 E2B QAT `UD-Q4_K_XL`".
    tagline: String(localized: "Expressive and steady, in Japanese too. Pick this one if unsure."),
    // Written as `gemma4E2B.id` rather than the literal so the two cannot
    // drift; `gemma4E2B` is declared first, so there is no forward reference
    // between the lazily-initialised statics.
    replacesModelID: gemma4E2B.id
  )

  /// Full production catalog, ordered by display preference — the QAT Gemma,
  /// Qwen, then the legacy Gemma build it replaces.
  ///
  /// **The trailing position is not decoration.** `gemma4E2B` is kept in the
  /// catalog under § "ADD-and-keep" above and is filtered out of the user-facing
  /// lists by `ModelManager.visibleCatalog` once it is absent from disk, so for a
  /// new install this array renders two rows. Removing it here instead would take
  /// `lookup` down with it — see that section for the four things that breaks.
  ///
  /// One instruction still binds a future editor of `gemma4E2BQAT`: **do not
  /// "fix" it into a removal-supersede** of `gemma4E2B`. That forces every
  /// existing user to re-download 2.62 GB with no way back if the QAT build
  /// misbehaves on their device.
  ///
  /// It departs from the curation policy's distinct-character bar and from
  /// `ModelDescriptor.shortDisplayName`'s no-build-variant principle as well —
  /// both, with the cost analysis, in that same eval-log entry and #1487.
  nonisolated static let catalog: [ModelDescriptor] = [gemma4E2BQAT, qwen34B, gemma4E2B]

  /// ID of the model selected by default for new users (first-run onboarding fallback).
  ///
  /// Distinct from `recommendedModelID`: this drives `ModelManager.resolveInitialActiveID`
  /// as the resolve-order fallback when no persisted active id exists. It is NOT the
  /// picker UI's "推奨" badge source — picker consults `recommendedModelID` instead.
  nonisolated static let defaultInitialModelID: ModelID = gemma4E2BQAT.id

  /// ID surfaced in the first-launch model picker as the "推奨" badge.
  ///
  /// Identity-distinct from `defaultInitialModelID` (the onboarding fallback) so
  /// future schemas — multi-recommended models, conditional recommendation by
  /// device class, A/B-tested rollouts — don't have to reshape the fallback field.
  /// Currently aliases to the same value as `defaultInitialModelID`, but the two
  /// must not be tested for equality; tests should assert each independently
  /// against the registered catalog.
  nonisolated static let recommendedModelID: ModelID = gemma4E2BQAT.id

  /// Returns the catalog descriptor matching `id`, or `nil` if no descriptor exists.
  ///
  /// Strict resolution: callers wanting a fallback (e.g., active model for unknown
  /// gallery `recommendedModel` values) should compose with `ModelManager.activeModelID`
  /// explicitly rather than baking that policy into this helper.
  nonisolated static func lookup(id: ModelID) -> ModelDescriptor? {
    catalog.first { $0.id == id }
  }

  /// The catalog member that takes over from `id` under § "ADD-and-keep", or
  /// `nil` when nothing replaces it.
  ///
  /// `catalog` is an explicit parameter rather than defaulting to ``catalog``:
  /// `ModelManager` filters *its own* catalog, which tests and previews
  /// substitute, and a helper that silently consulted the production array
  /// would answer about a different set than the caller is filtering. This is
  /// the single implementation of the replacement relation — both consumers
  /// (`ModelManager.visibleCatalog` and `RecommendedModelStatus.compute`) go
  /// through it. Do not add a second predicate deriving it another way; two
  /// that can disagree is worse than one that can be wrong.
  nonisolated static func replacement(
    for id: ModelID,
    in catalog: [ModelDescriptor]
  ) -> ModelDescriptor? {
    catalog.first { $0.replacesModelID == id }
  }

  /// The cheapest build that **satisfies** a recommendation naming `id`, given
  /// what is on this device: its replacement (§ "ADD-and-keep") when that is
  /// already on disk, else the declared build when *that* is, else the
  /// replacement. `nil` only when `id` is in no catalog entry at all.
  ///
  /// Every `docs/gallery/gallery.json` entry recommends the Q4_K_M Gemma build,
  /// and that feed is fetched live by **already-shipped** app versions, so it
  /// cannot be repointed at an id those builds do not know
  /// (`URLSessionGalleryService.defaultIndexURL`). Resolving on the app side
  /// instead is what stops a fresh install being pushed toward a build hidden
  /// from every list surface.
  ///
  /// **Why `state` rather than a flat forward-resolve.** A user who already has
  /// the replaced build on disk but is running some *third* model is satisfied
  /// by a free switch; resolving unconditionally would offer them a multi-GB
  /// download of a successor to a model they already own, on every gallery
  /// screen. So the rule is the cheapest satisfying option — and where two
  /// options cost the same, the newer one. A fresh install, where neither is on
  /// disk, still lands on the replacement.
  ///
  /// **The order of the two `.ready` checks is the tie-break, not a detail.**
  /// Asking the declared build first hands a both-builds-on-disk user the
  /// *superseded* one for free: the switch affordance would point backwards, and
  /// the gallery's "Recommended model" row would name the replaced build to
  /// someone already running its successor.
  ///
  /// This answers "which build do we act on", **not** "is the active model
  /// already acceptable" — that one is state-free and stays in
  /// `RecommendedModelStatus`'s Rule 4, which tests the active id against the
  /// declared id and its replacement directly. Routing it through here instead
  /// would offer a QAT-active user a *downgrade* switch to the replaced build
  /// whenever they happen to still have it on disk.
  ///
  /// `nil`-returning on an unknown id is deliberate: it keeps the forward-compat
  /// path for an *older* app reading a *newer* feed —
  /// `RecommendedModelStatus.unknownModel` and the "Unknown model (%@)" display
  /// fallback both key on it.
  nonisolated static func recommendationTarget(
    for id: ModelID,
    state: [ModelID: ModelState]
  ) -> ModelDescriptor? {
    guard let declared = lookup(id: id) else { return nil }
    let successor = replacement(for: id, in: catalog)
    if let successor, case .ready = state[successor.id] { return successor }
    if case .ready = state[declared.id] { return declared }
    return successor ?? declared
  }

  /// Returns diagnostic reasons if `catalog` contains duplicate `id` or `fileName` values.
  /// Empty result means the catalog is valid. Exposed for testability; `validateNoCollisions`
  /// wraps this in a precondition.
  nonisolated static func findCollisions(in catalog: [ModelDescriptor]) -> [String] {
    var reasons: [String] = []

    var seenIDs: [ModelID: Int] = [:]
    var seenFileNames: [String: Int] = [:]

    for (index, descriptor) in catalog.enumerated() {
      if let previousIndex = seenIDs[descriptor.id] {
        reasons.append(
          "Duplicate id \"\(descriptor.id)\" at indices \(previousIndex) and \(index)")
      } else {
        seenIDs[descriptor.id] = index
      }

      if let previousIndex = seenFileNames[descriptor.fileName] {
        reasons.append(
          "Duplicate fileName \"\(descriptor.fileName)\" at indices \(previousIndex) and \(index)"
        )
      } else {
        seenFileNames[descriptor.fileName] = index
      }
    }

    return reasons
  }

  /// Precondition-checks the production catalog for duplicate `id` / `fileName` values.
  /// Called once at app launch from `PasturaApp.initialize()` to fail fast on
  /// catalog collisions before they can corrupt `ModelManager.state` lookups
  /// or filesystem paths.
  nonisolated static func validateNoCollisions() {
    let reasons = findCollisions(in: catalog)
    precondition(
      reasons.isEmpty,
      "ModelRegistry catalog collisions: \(reasons.joined(separator: ", "))"
    )
  }
}

extension ModelRegistry {
  /// Resolves a persisted `SimulationRecord.modelIdentifier` (stored as a
  /// descriptor's `displayName`, e.g. "Gemma 4 E2B (Q4_K_M)") to its short
  /// label ("Gemma 4 E2B") for the highlight share card (#1070), so the
  /// past-results card shows the same model name as the live card (which reads
  /// `shortDisplayName` directly). Falls back to the raw identifier when it
  /// matches no catalog descriptor (a superseded model), and `nil` when absent.
  nonisolated static func shortDisplayName(forIdentifier identifier: String?) -> String? {
    guard let identifier, !identifier.isEmpty else { return nil }
    let match = catalog.first { $0.displayName == identifier }
    return match?.shortDisplayName ?? match?.displayName ?? identifier
  }
}
