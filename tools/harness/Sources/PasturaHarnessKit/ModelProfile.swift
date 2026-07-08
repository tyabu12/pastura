import Foundation

/// Inference-parameter profile for a GGUF model the harness can drive.
///
/// Harness-local mirror of the load-bearing fields of the app's
/// `ModelRegistry` entry (`Pastura/Pastura/App/ModelRegistry.swift`) — the
/// registry itself is App-layer, outside this package (ADR-013 §4). The
/// pin test in `ModelProfileTests` guards drift between the two.
package struct ModelProfile: Sendable, Equatable {
  /// Registry id. Mirrors `ModelDescriptor.id` — the key accepted by the
  /// harness `--profile` flag.
  package let id: String
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
  /// Expected GGUF file name, mirroring the registry's `fileName`. Used
  /// ONLY for a non-fatal mismatch warning (`mismatchWarning(forModelPath:)`)
  /// — never enforced, since operators may rename GGUF files locally.
  package let expectedFileName: String
  /// Expected SHA-256 of the GGUF file. NOT hashed by the harness at run
  /// time (re-hashing ~3 GB nightly is wasteful); the operator verifies
  /// once via `shasum -a 256` when installing the model file.
  package let expectedSHA256: String

  package init(
    id: String, name: String, stopSequence: String, systemPromptSuffix: String?,
    assistantPrefix: String?, expectedFileName: String, expectedSHA256: String
  ) {
    self.id = id
    self.name = name
    self.stopSequence = stopSequence
    self.systemPromptSuffix = systemPromptSuffix
    self.assistantPrefix = assistantPrefix
    self.expectedFileName = expectedFileName
    self.expectedSHA256 = expectedSHA256
  }

  /// Gemma 4 E2B Q4_K_M — the shipping on-device model (ADR-002).
  package static let gemma4E2B = ModelProfile(
    id: "gemma-4-e2b-q4-k-m",
    name: "Gemma 4 E2B (Q4_K_M)",
    stopSequence: "<|im_end|>",
    systemPromptSuffix: nil,
    assistantPrefix: nil,
    expectedFileName: "gemma-4-E2B-it-Q4_K_M.gguf",
    expectedSHA256: "ac0069ebccd39925d836f24a88c0f0c858d20578c29b21ab7cedce66ee576845"
  )

  /// Qwen 3 4B Q4_K_M — second selectable on-device model (ADR-002 update).
  package static let qwen34B = ModelProfile(
    id: "qwen-3-4b-q4-k-m",
    name: "Qwen 3 4B (Q4_K_M)",
    stopSequence: "<|im_end|>",
    systemPromptSuffix: "/no_think",
    // Prefill the assistant turn with the empty-thinking marker so Qwen 3
    // bypasses thinking mode entirely. Issue #366 — without this, Qwen
    // emits `<think>` as its first sampled token and the GBNF grammar
    // sampler crashes on `accept_token` (uncaught C++ exception). The
    // `/no_think` system suffix above is a soft hint only and does not
    // prevent the leading `<think>` token; this prefill is the
    // load-bearing fix.
    assistantPrefix: "<think>\n\n</think>\n\n",
    expectedFileName: "Qwen3-4B-Q4_K_M.gguf",
    expectedSHA256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5"
  )

  /// Sarashina 2.2 3B Q4_K_M — Stage-0 evaluation candidate (model-validation
  /// pipeline, intake #979). Unlike `gemma4E2B` / `qwen34B`, this has **no**
  /// `App/ModelRegistry` entry yet: it is a candidate under the `/model-eval`
  /// Mac-filter gate, not a shipped model. Registration (a `ModelDescriptor`)
  /// happens only after the ADR-011 real-device accept gate.
  ///
  /// Gate-1 result (2026-07-08): **NO-GO**, blocked (not a clean quality
  /// reject). 3 of 6 battery cells hard-failed with "Model generated no
  /// output tokens": this 3B intermittently samples EOG/EOS at position 0
  /// under the GBNF grammar, yielding an empty generation. The shipped
  /// SafeSampler crash-hardening (#253/#371) holds — it does NOT crash — but
  /// the empty output exhausts the retry budget and aborts the run. That is
  /// the deferred, inference-side #751 sub-class 2 (empty-output / EOG-at-0),
  /// NOT the #366 crash class. Stochastic + cumulative: simple/short scenarios
  /// (bokete) complete, longer/reflect-heavy ones (word_wolf, PD) fail. The
  /// values below are correct (the failure is this inference-side interaction,
  /// not a wrong field); the profile is retained as the reproduction case for
  /// #751 and a re-eval after it lands. See `data/models/eval-digest.md` + #979.
  package static let sarashina223B = ModelProfile(
    id: "sarashina-2-2-3b-q4-k-m",
    name: "Sarashina 2.2 3B (Q4_K_M)",
    // Sarashina 2.2 (SB Intuitions, MIT) formats turns as
    // `<|system|>…</s><|user|>…</s><|assistant|>…</s>` with eos `</s>`, and
    // has no thinking mode — so, unlike Qwen (#366), it needs neither a
    // `/no_think` suffix nor a `<think>` assistant prefill. The stop sequence
    // is the plain eos `</s>`; suffix and prefix are nil.
    stopSequence: "</s>",
    systemPromptSuffix: nil,
    assistantPrefix: nil,
    expectedFileName: "sarashina2.2-3b-instruct-v0.1-Q4_K_M.gguf",
    expectedSHA256: "d96f4d98eb528df26e8bc09ab81a1d165be4fce67616739e65980bed9038f0f2"
  )

  /// Known profiles the harness `--profile` flag can select, gemma first
  /// as the default.
  package static let all: [ModelProfile] = [gemma4E2B, qwen34B, sarashina223B]

  /// Looks up a known profile by its registry `id`, or `nil` if unknown.
  package static func named(_ id: String) -> ModelProfile? {
    all.first { $0.id == id }
  }

  /// Non-fatal warning when `path`'s file name doesn't match
  /// `expectedFileName` (case-insensitive) — surfaces model↔profile
  /// mismatches (the #366 crash class) without blocking renamed files.
  /// Returns `nil` when the file name matches.
  package func mismatchWarning(forModelPath path: String) -> String? {
    let actualFileName = (path as NSString).lastPathComponent
    guard actualFileName.caseInsensitiveCompare(expectedFileName) != .orderedSame else {
      return nil
    }
    return
      "Warning: model file \"\(actualFileName)\" does not match profile \"\(id)\"'s "
      + "expected file name \"\(expectedFileName)\" — prompt-format hints (stop sequence, "
      + "assistant prefill) may be wrong for this file; pass --profile explicitly to override."
  }
}
