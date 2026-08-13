import Foundation
import Testing

@testable import Pastura

// MARK: - Configuration

/// Reads Qwen-specific integration test settings from environment variables.
private enum QwenConfig {
  /// Gate: tests run only when `LLAMACPP_INTEGRATION=1` AND
  /// `LLAMACPP_QWEN_MODEL_PATH` is set to an absolute path.
  /// Both conditions together prevent the Qwen tests from accidentally running
  /// with Gemma's `LLAMACPP_MODEL_PATH` and producing false negatives.
  static var isEnabled: Bool {
    guard ProcessInfo.processInfo.environment["LLAMACPP_INTEGRATION"] == "1" else {
      return false
    }
    guard let path = ProcessInfo.processInfo.environment["LLAMACPP_QWEN_MODEL_PATH"],
      !path.isEmpty
    else {
      return false
    }
    return true
  }

  /// Absolute path to the Qwen 3 4B Q4_K_M GGUF file. Empty string when the
  /// env var is unset; `isEnabled` guards actual consumption.
  static var modelPath: String {
    ProcessInfo.processInfo.environment["LLAMACPP_QWEN_MODEL_PATH"] ?? ""
  }
}

// MARK: - Tests (joins the serialized `LlamaCppIntegrationTests` suite)

/// Pre-implementation verification for Qwen 3 4B Q4_K_M — gates PR B of
/// the multi-model support work (#203). These tests must pass against a
/// local Qwen GGUF before PR B's user-facing UI is implemented.
///
/// Run with:
/// ```
/// source scripts/sim-dest.sh
/// LLAMACPP_INTEGRATION=1 \
///   LLAMACPP_QWEN_MODEL_PATH=/path/to/Qwen3-4B-Q4_K_M.gguf \
///   xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
///   -destination "$DEST" \
///   -only-testing PasturaTests/LlamaCppIntegrationTests
/// ```
///
/// Failure playbook:
/// - Test (a) fails → the Q4_K_M quantization is incompatible with
///   llama.cpp's chatml fallback path. Revise plan to add a
///   `chatTemplateOverride` field on `ModelDescriptor`.
/// - Test (b) fails → the `<think>\n\n</think>\n\n` assistant prefill
///   (`ModelDescriptor.assistantPrefix`) is being dropped or has the wrong
///   shape. Confirm `LlamaCppService.applyChatTemplate` appends the prefix
///   to the formatted prompt after `llama_chat_apply_template`. The
///   `/no_think` system suffix is a soft training hint and is not the
///   load-bearing mechanism — do NOT debug this test by altering the
///   suffix. History: Issue #366 — without the prefill, Qwen 3 emits
///   `<think>` (token 151667) as its first generated token, crashing
///   the grammar sampler.
/// - Test (c) fails → schema-constrained generation hit the grammar-sampler
///   crash that motivated the prefill. The whole process terminates
///   (uncaught C++ exception); test (c) regresses test-process side too.
extension LlamaCppIntegrationTests {

  // MARK: - Helpers

  private func makeQwenService() -> LlamaCppService {
    // Mirror `ModelRegistry.qwen34B` — keep `/no_think` and the prefill in
    // lockstep with production so integration regressions track real builds.
    LlamaCppService(
      modelPath: QwenConfig.modelPath,
      stopSequence: "<|im_end|>",
      // Stated rather than defaulted, even though `.chatML` is the value Qwen
      // wants: a defaulted site stops tracking the descriptor it mirrors (#1422).
      turnMarkers: .chatML,
      modelIdentifier: "Qwen 3 4B (Q4_K_M)",
      systemPromptSuffix: "/no_think",
      assistantPrefix: "<think>\n\n</think>\n\n"
    )
  }

  // MARK: - Test (a): Qwen GGUF loads and generates

  /// Verifies that Qwen 3 4B Q4_K_M loads through `LlamaCppService` without
  /// chat-template or sampler surprises. Generating a short, JSON-shaped
  /// response proves the full pipeline (load → tokenize → sample → stop →
  /// decode → stop-sentinel match) works for this model.
  @Test(
    "Qwen: loads and produces non-empty output",
    .enabled(if: QwenConfig.isEnabled),
    .timeLimit(.minutes(3))
  )
  func qwenLoadsAndGenerates() async throws {
    let service = makeQwenService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: "Reply with JSON only: {\"greeting\": \"hello\"}",
      user: "Say hello."
    )

    #expect(!result.isEmpty, "Qwen generated empty output")
    #expect(result.count > 5, "Qwen output suspiciously short: \(result)")
    // Output should not contain leaked <|im_end|> — same contract as Gemma
    #expect(
      !result.contains("<|im_end|>"),
      "Qwen output contains <|im_end|> — stop sequence detection failed. Raw: \(result)"
    )
  }

  // MARK: - Test (b): /no_think suppresses thinking

  /// Verifies that `systemPromptSuffix="/no_think"` injected via
  /// `applyChatTemplate` actually suppresses Qwen 3's thinking-mode output
  /// (`<think>...</think>` blocks). Without this, a thinking-mode Qwen
  /// generation can emit hundreds of thought tokens before the JSON, which
  /// exhausts `maxTokens=1000` and produces empty/truncated parses.
  ///
  /// A failure here means the descriptor-level suffix is being dropped,
  /// applied to the wrong role, or not recognized by the model — any of
  /// which warrants plan revision before shipping PR B.
  @Test(
    "Qwen: /no_think system suffix prevents <think> blocks",
    .enabled(if: QwenConfig.isEnabled),
    .timeLimit(.minutes(3))
  )
  func qwenNoThinkSuppressesThinking() async throws {
    let service = makeQwenService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly."
    )

    #expect(
      !result.contains("<think>"),
      "Qwen emitted <think> block despite assistant prefill. Raw: \(result)"
    )
    #expect(
      !result.contains("</think>"),
      "Qwen emitted </think> close tag despite assistant prefill. Raw: \(result)"
    )
  }

  // MARK: - Test (c): Schema-constrained generate does NOT crash on <think>

  /// Verifies that schema-constrained generation does not regress the
  /// grammar-sampler crash that motivated `assistantPrefix` (Issue #366).
  ///
  /// Without the `<think>\n\n</think>\n\n` prefill, Qwen 3 emits `<think>`
  /// (token 151667) as its first generated token. The GBNF grammar's `root`
  /// rule cannot accept that piece, so `llama_grammar_accept_token` throws
  /// `std::runtime_error: Unexpected empty grammar stack` — an uncaught C++
  /// exception that terminates the test process. A regression here will
  /// take down the whole test runner, not just this test; if you see the
  /// xctest harness exit without reporting, this is the prime suspect.
  ///
  /// This test exercises the same code path as Engine's
  /// `speak_all` / `choose` handlers when they wire GBNF grammar through
  /// `LLMService.generate(system:user:schema:)`.
  @Test(
    "Qwen: schema-constrained generate does not crash on <think>",
    .enabled(if: QwenConfig.isEnabled),
    .timeLimit(.minutes(3))
  )
  func qwenWithGrammarDoesNotCrash() async throws {
    let service = makeQwenService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let schema = OutputSchema(fields: [
      OutputSchema.Field(name: "statement", kind: .string)
    ])

    // Reaching this `#expect` means no C++ exception terminated the process.
    let result = try await service.generate(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly.",
      schema: schema
    )

    #expect(!result.isEmpty, "Qwen produced empty output under grammar")
    #expect(
      result.contains("{") && result.contains("}"),
      "Qwen output is not JSON-shaped under grammar. Raw: \(result)"
    )
  }
}
