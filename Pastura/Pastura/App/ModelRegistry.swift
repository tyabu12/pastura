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
    // absent from this model's vocabulary, and replacing it would mean guessing
    // what text a Gemma hallucination spells out. See the canonical note on
    // `LlamaCppService.stopSequence` (#1417; behaviour half #1422).
    stopSequence: "<|im_end|>",
    minRAM: 6_500_000_000,
    modelInfoURL: unsafeURL("https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF"),
    systemPromptSuffix: nil,
    tagline: String(localized: "Balanced choice. Rich, considered responses.")
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
    // runtime config — it leans on size/footprint instead.
    tagline: String(localized: "Compact and nimble. A small download you can try freely.")
  )

  /// Full production catalog, ordered by display preference (Gemma first, Qwen second).
  nonisolated static let catalog: [ModelDescriptor] = [gemma4E2B, qwen34B]

  /// ID of the model selected by default for new users (first-run onboarding fallback).
  ///
  /// Distinct from `recommendedModelID`: this drives `ModelManager.resolveInitialActiveID`
  /// as the resolve-order fallback when no persisted active id exists. It is NOT the
  /// picker UI's "推奨" badge source — picker consults `recommendedModelID` instead.
  nonisolated static let defaultInitialModelID: ModelID = gemma4E2B.id

  /// ID surfaced in the first-launch model picker as the "推奨" badge.
  ///
  /// Identity-distinct from `defaultInitialModelID` (the onboarding fallback) so
  /// future schemas — multi-recommended models, conditional recommendation by
  /// device class, A/B-tested rollouts — don't have to reshape the fallback field.
  /// Currently aliases to the same value as `defaultInitialModelID`, but the two
  /// must not be tested for equality; tests should assert each independently
  /// against the registered catalog.
  nonisolated static let recommendedModelID: ModelID = gemma4E2B.id

  /// Returns the catalog descriptor matching `id`, or `nil` if no descriptor exists.
  ///
  /// Strict resolution: callers wanting a fallback (e.g., active model for unknown
  /// gallery `recommendedModel` values) should compose with `ModelManager.activeModelID`
  /// explicitly rather than baking that policy into this helper.
  nonisolated static func lookup(id: ModelID) -> ModelDescriptor? {
    catalog.first { $0.id == id }
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
