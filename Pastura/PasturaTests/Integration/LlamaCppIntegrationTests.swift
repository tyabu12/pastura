import Foundation
import Testing

@testable import Pastura

// MARK: - Configuration

/// Reads llama.cpp integration test settings from environment variables.
private enum LlamaCppConfig {
  /// Gate: must be exactly "1" to enable these tests.
  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["LLAMACPP_INTEGRATION"] == "1"
  }

  /// Absolute path to a GGUF model file.
  /// Defaults to `~/Models/gemma-4-e2b-it-Q4_K_M.gguf`.
  static var modelPath: String {
    ProcessInfo.processInfo.environment["LLAMACPP_MODEL_PATH"]
      ?? "\(NSHomeDirectory())/Models/gemma-4-e2b-it-Q4_K_M.gguf"
  }
}

// MARK: - Tests

/// Integration tests that run against a real GGUF model via llama.cpp.
///
/// Gated by `LLAMACPP_INTEGRATION=1` environment variable. These tests are skipped
/// in normal CI runs and require a local GGUF model file.
///
/// Run with:
/// ```
/// source scripts/sim-dest.sh
/// LLAMACPP_INTEGRATION=1 LLAMACPP_MODEL_PATH=/path/to/model.gguf \
///   xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
///   -destination "$DEST" -only-testing PasturaTests/LlamaCppIntegrationTests
/// ```
@Suite(.serialized, .enabled(if: LlamaCppConfig.isEnabled))
struct LlamaCppIntegrationTests {

  // MARK: - Helpers

  private func makeService() -> LlamaCppService {
    LlamaCppService(modelPath: LlamaCppConfig.modelPath)
  }

  // MARK: - Test 1: Load/unload lifecycle

  @Test(.timeLimit(.minutes(2)))
  func loadAndUnloadLifecycle() async throws {
    let service = makeService()
    #expect(!service.isModelLoaded)

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - Test 1b: loadModel idempotency (issue #114)

  @Test(.timeLimit(.minutes(3)))
  func loadModelTwiceIsIdempotent() async throws {
    // Regression test for issue #114: calling loadModel() while already loaded
    // must free the prior _model/_context, not leak ~3GB of Gemma buffers.
    // A memory leak is not directly assertable without Instruments, so this
    // test verifies the happy-path invariants that lock in the defensive
    // unload: both loads succeed, state stays consistent, and the final
    // unload completes cleanly (a stale dangling pointer would crash here).
    let service = makeService()

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - Test 2: Simple generation

  @Test(.timeLimit(.minutes(3)))
  func simpleGenerationProducesOutput() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: "You are a helpful assistant. Respond in JSON with a 'greeting' field.",
      user: "Say hello."
    )

    #expect(!result.isEmpty, "Generation produced empty output")
    #expect(result.count > 5, "Generation suspiciously short: \(result)")
  }

  // MARK: - Test 3: JSON output parses via JSONResponseParser

  @Test(.timeLimit(.minutes(3)))
  func jsonResponseParserHandlesOutput() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly."
    )

    let parsed = try JSONResponseParser().parse(result)
    let statement = parsed.statement ?? ""
    #expect(!statement.isEmpty, "Parsed statement is empty. Raw: \(result)")
  }

  // MARK: - Test 4: Generation stops at <|im_end|> token

  @Test(.timeLimit(.minutes(3)))
  func generationStopsAtImEnd() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly."
    )

    // Output should not contain leaked <|im_end|> token
    #expect(
      !result.contains("<|im_end|>"),
      "Raw output contains <|im_end|> — stop token not working. Output: \(result)"
    )
    // Output should be well under maxTokens (1000 tokens ≈ 4000 chars).
    // A runaway generation hitting maxTokens indicates the stop token failed.
    #expect(
      result.count < 2000,
      "Output suspiciously long (\(result.count) chars) — may have hit maxTokens"
    )
  }

  // MARK: - Test 5a: Streaming yields incremental deltas, isFinal once

  @Test(.timeLimit(.minutes(3)))
  func streamingYieldsIncrementalDeltas() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    var deltas: [String] = []
    var finalChunkCount = 0
    var lastCompletionTokens: Int?

    for try await chunk in service.generateStream(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly."
    ) {
      if chunk.isFinal {
        finalChunkCount += 1
        lastCompletionTokens = chunk.completionTokens
      } else {
        deltas.append(chunk.delta)
      }
    }

    // At least two non-final chunks means real streaming happened (rather
    // than a single-shot fallback).
    #expect(deltas.count > 1, "Expected multiple chunks, got \(deltas.count)")
    #expect(finalChunkCount == 1, "Expected exactly one final chunk")
    #expect(
      (lastCompletionTokens ?? 0) > 0,
      "Final chunk should carry completionTokens"
    )

    // None of the emitted deltas may contain the stop sequence — it must
    // be detected and trimmed before emission.
    for delta in deltas {
      #expect(
        !delta.contains("<|im_end|>"),
        "Delta leaked <|im_end|>: \(delta)"
      )
    }

    // Concatenation of all deltas produces the same final text the
    // non-streaming `generate` path would return.
    let streamedText = deltas.joined()
    let parsed = try JSONResponseParser().parse(streamedText)
    let statement = parsed.statement ?? ""
    #expect(!statement.isEmpty, "Streamed text failed to parse. Raw: \(streamedText)")
  }

  // MARK: - Test 5b: Stream and non-stream produce equivalent text

  @Test(.timeLimit(.minutes(5)))
  func streamAndGenerateAgreeOnFinalText() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let system = "Reply with JSON only: {\"echo\": \"ack\"}"
    let user = "Echo."

    let nonStreamed = try await service.generate(system: system, user: user)

    var streamed = ""
    for try await chunk in service.generateStream(system: system, user: user)
    where !chunk.isFinal {
      streamed += chunk.delta
    }

    // Don't expect byte-for-byte equality — sampling is stochastic across
    // runs — but both paths should parse as JSON and have an echo field.
    let nonStreamedParsed = try JSONResponseParser().parse(nonStreamed)
    let streamedParsed = try JSONResponseParser().parse(streamed)
    #expect(nonStreamedParsed.fields["echo"] != nil)
    #expect(streamedParsed.fields["echo"] != nil)
  }

  // MARK: - Test 6: Multiple sequential generations (KV cache clear)

  @Test(.timeLimit(.minutes(5)))
  func multipleSequentialGenerations() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    for i in 1...3 {
      let result = try await service.generate(
        system: "Reply with JSON: {\"number\": \"\(i)\"}",
        user: "What number?"
      )
      #expect(!result.isEmpty, "Generation \(i) produced empty output")
    }
  }
}
