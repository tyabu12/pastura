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
    stopSequence: "<|im_end|>",
    minRAM: 6_500_000_000,
    modelInfoURL: unsafeURL("https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF"),
    systemPromptSuffix: nil,
    tagline: String(localized: "Balanced choice. Rich expression and measured reasoning.")
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
    // Reuses an existing translated catalog key (originally the conditional
    // `ModelPickerView.hint(for:)` for `/no_think` descriptors). Item 6 of
    // the picker redesign removes that helper and routes the tagline through
    // this field instead.
    tagline: String(localized: "Lightweight reasoning mode — faster responses, leaner footprint.")
  )

  /// Lower-tier Gemma 3 1B IT — added for 6 GB RAM device support (#477).
  /// 8 GB+ devices retain Gemma 4 E2B as the heavier default; the picker /
  /// `ModelManager` gating use per-descriptor `minRAM` to route 6 GB tier
  /// devices (iPhone 13/14/15 standard, SE 3rd) to this descriptor.
  ///
  /// Verified compatible with Gemma 4's `LlamaCppService` plumbing (same
  /// unsloth GGUF → ChatML `<|im_end|>` stop token; no `<think>` prefill
  /// required since Gemma 3 has no thinking mode).
  nonisolated static let gemma31B: ModelDescriptor = ModelDescriptor(
    id: "gemma-3-1b-it-q4-k-m",
    displayName: "Gemma 3 1B IT (Q4_K_M)",
    shortDisplayName: "Gemma 3 1B",
    vendor: "Google",
    vendorURL: unsafeURL("https://deepmind.google"),
    downloadURL: unsafeURL(
      "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/f7694be509de1c4ab9afc29f8353a315326c64f3/gemma-3-1b-it-Q4_K_M.gguf"
    ),
    fileName: "gemma-3-1b-it-Q4_K_M.gguf",
    // Sentinel placeholders for the PoC draft (#477). `fileSize: 0` trips
    // the "skip size-mismatch deletion" path in `ModelManager.computeState`,
    // and `sha256: ""` trips the "skip integrity check" path in
    // `ModelManager.verifyDownloadIntegrity`. Both are intentional for
    // draft state — PoC measures real values on a 6 GB device and replaces
    // them before the PR moves out of draft. `validateProductionReadiness()`
    // (next commit) traps these sentinels in Release builds so they cannot
    // ship to TestFlight.
    fileSize: 0,
    sha256: "",
    stopSequence: "<|im_end|>",
    // 5.5 GB — leaves OS-overhead headroom on iPhone 13/14/15 standard
    // (6 GB physical). Concrete floor is tunable from PoC memory measurements.
    minRAM: 5_500_000_000,
    modelInfoURL: unsafeURL("https://huggingface.co/unsloth/gemma-3-1b-it-GGUF"),
    systemPromptSuffix: nil,
    // Gemma 3 has no thinking-mode token (cf. Qwen 3's `<think>`-driven
    // crash #366), so no assistant-turn prefill is required.
    assistantPrefix: nil,
    tagline: String(localized: "Lightest of the lineup. Friendly to older devices.")
  )

  /// Full production catalog, ordered by display preference
  /// (Gemma 4 E2B → Qwen 3 4B → Gemma 3 1B).
  nonisolated static let catalog: [ModelDescriptor] = [gemma4E2B, qwen34B, gemma31B]

  /// ID of the model selected by default for new users (first-run onboarding fallback),
  /// resolved per the device's physical memory.
  ///
  /// Drives `ModelManager.resolveInitialActiveID` as the resolve-order fallback
  /// when no persisted active id exists. Distinct from `recommendedModelID(for:)`
  /// (the picker UI "推奨" badge source) so the two can diverge in future schemas
  /// (multi-recommended rollouts, A/B-tested defaults) — kept literally parallel
  /// here so a future divergence only touches one function.
  ///
  /// Tier table (lower bound exclusive — exactly `6.5 GB` routes to the 8 GB+ tier):
  ///   - `< 6.5 GB` (6 GB tier — iPhone 13/14/15 standard, SE 3) → `gemma31B`
  ///   - `≥ 6.5 GB` (8 GB+ tier — iPhone 15 Pro and newer)       → `gemma4E2B`
  nonisolated static func defaultInitialModelID(for deviceRAM: UInt64) -> ModelID {
    switch deviceRAM {
    case ..<6_500_000_000: return gemma31B.id
    default: return gemma4E2B.id
    }
  }

  /// ID surfaced in the first-launch model picker as the "推奨" badge, resolved
  /// per the device's physical memory.
  ///
  /// Identity-distinct from `defaultInitialModelID(for:)` (the onboarding
  /// fallback) so future schemas — conditional recommendation by device class,
  /// A/B-tested rollouts — don't have to reshape the fallback field. The two
  /// currently share the same tier table; tests must not assert equality, only
  /// per-function resolution to a registered descriptor.
  nonisolated static func recommendedModelID(for deviceRAM: UInt64) -> ModelID {
    switch deviceRAM {
    case ..<6_500_000_000: return gemma31B.id
    default: return gemma4E2B.id
    }
  }

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
  /// Call once at app launch (future Item — this PR only provides the API).
  nonisolated static func validateNoCollisions() {
    let reasons = findCollisions(in: catalog)
    precondition(
      reasons.isEmpty,
      "ModelRegistry catalog collisions: \(reasons.joined(separator: ", "))"
    )
  }

  /// Returns diagnostic reasons if `catalog` contains descriptors with PoC
  /// sentinel placeholders (`fileSize == 0` or empty `sha256`). Empty result
  /// means every descriptor carries integrity metadata suitable for Release
  /// shipment. Exposed for testability; `validateProductionReadiness` wraps
  /// this in a precondition.
  ///
  /// Background: PoC-draft descriptors (issue #477) intentionally carry
  /// sentinel placeholders that trip `ModelManager.computeState`'s
  /// `descriptor.fileSize > 0` size-check and `verifyDownloadIntegrity`'s
  /// `!descriptor.sha256.isEmpty` SHA-check. These sentinels MUST be
  /// replaced with measured values from on-device PoC before any catalog
  /// descriptor ships to TestFlight — otherwise a corrupted GGUF download
  /// would land as `.ready` without integrity verification.
  nonisolated static func findSentinels(in catalog: [ModelDescriptor]) -> [String] {
    var reasons: [String] = []
    for descriptor in catalog {
      if descriptor.fileSize <= 0 {
        reasons.append(
          "Descriptor '\(descriptor.id)' has sentinel fileSize \(descriptor.fileSize) "
            + "— must be > 0 in Release builds (#477 PoC).")
      }
      if descriptor.sha256.isEmpty {
        reasons.append(
          "Descriptor '\(descriptor.id)' has empty sha256 "
            + "— must be set to the on-device-measured SHA-256 in Release builds (#477 PoC).")
      }
    }
    return reasons
  }

  /// Precondition-checks the production catalog for PoC sentinel placeholders.
  /// Call from `PasturaApp.initialize` under `#if !DEBUG` so Release builds
  /// crash fast at launch if sentinels haven't been replaced with measured
  /// values from on-device PoC. Debug builds skip the check so PoC iteration
  /// is unblocked — see `findSentinels(in:)` doc for the integrity rationale.
  nonisolated static func validateProductionReadiness() {
    let reasons = findSentinels(in: catalog)
    precondition(
      reasons.isEmpty,
      "ModelRegistry catalog not production-ready: \(reasons.joined(separator: " "))"
    )
  }
}
