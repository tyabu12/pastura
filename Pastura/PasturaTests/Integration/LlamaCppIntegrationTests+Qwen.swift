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
/// - Test (b) fails → `/no_think` in the system prompt does not suppress
///   thinking mode. Try moving the suffix to the user message
///   (introduce `PromptSuffixPosition` enum) OR raise `maxTokens` per
///   descriptor so the JSON survives the thinking prefix.
extension LlamaCppIntegrationTests {

  // MARK: - Helpers

  private func makeQwenService() -> LlamaCppService {
    LlamaCppService(
      modelPath: QwenConfig.modelPath,
      stopSequence: "<|im_end|>",
      modelIdentifier: "Qwen 3 4B (Q4_K_M)",
      systemPromptSuffix: "/no_think"
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
      "Qwen emitted <think> block despite /no_think suffix. Raw: \(result)"
    )
    #expect(
      !result.contains("</think>"),
      "Qwen emitted </think> close tag despite /no_think suffix. Raw: \(result)"
    )
  }
}
