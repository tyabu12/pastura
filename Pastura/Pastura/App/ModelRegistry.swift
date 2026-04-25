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
    systemPromptSuffix: nil
  )

  nonisolated static let qwen34B: ModelDescriptor = ModelDescriptor(
    id: "qwen-3-4b-q4-k-m",
    displayName: "Qwen 3 4B (Q4_K_M)",
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
    systemPromptSuffix: "/no_think"
  )

  /// Full production catalog, ordered by display preference (Gemma first, Qwen second).
  nonisolated static let catalog: [ModelDescriptor] = [gemma4E2B, qwen34B]

  /// ID of the model selected by default for new users (first-run onboarding fallback).
  nonisolated static let defaultInitialModelID: ModelID = gemma4E2B.id

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
}
