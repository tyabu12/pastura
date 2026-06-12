import Foundation

/// Inference-parameter profile for a GGUF model the harness can drive.
///
/// Harness-local mirror of the load-bearing fields of the app's
/// `ModelRegistry` entry (`Pastura/Pastura/App/ModelRegistry.swift`) — the
/// registry itself is App-layer, outside this package (ADR-013 §4). The
/// pin test in `ModelProfileTests` guards drift between the two.
package struct ModelProfile: Sendable, Equatable {
  /// Human-readable model label, used as `LlamaCppService.modelIdentifier`.
  package let name: String
  /// Stop sequence terminating each generation.
  package let stopSequence: String
  /// Optional suffix appended to every system prompt.
  package let systemPromptSuffix: String?
  /// Optional assistant-turn prefill. Gemma needs none — the
  /// `<think>...</think>` prefill in the app registry is Qwen-only
  /// (see `.claude/rules/engine.md` § llama.cpp traps).
  package let assistantPrefix: String?
  /// Expected SHA-256 of the GGUF file. NOT hashed by the harness at run
  /// time (re-hashing ~3 GB nightly is wasteful); the operator verifies
  /// once via `shasum -a 256` when installing the model file.
  package let expectedSHA256: String

  package init(
    name: String, stopSequence: String, systemPromptSuffix: String?,
    assistantPrefix: String?, expectedSHA256: String
  ) {
    self.name = name
    self.stopSequence = stopSequence
    self.systemPromptSuffix = systemPromptSuffix
    self.assistantPrefix = assistantPrefix
    self.expectedSHA256 = expectedSHA256
  }

  /// Gemma 4 E2B Q4_K_M — the shipping on-device model (ADR-002).
  package static let gemma4E2B = ModelProfile(
    name: "Gemma 4 E2B (Q4_K_M)",
    stopSequence: "<|im_end|>",
    systemPromptSuffix: nil,
    assistantPrefix: nil,
    expectedSHA256: "ac0069ebccd39925d836f24a88c0f0c858d20578c29b21ab7cedce66ee576845"
  )
}
