import Foundation
import Testing

@testable import Pastura

/// Streaming half of ``LlamaCppIntegrationTests``, split out to keep the
/// original file under swiftlint's 400-line `file_length` cap.
///
/// Declared as an `extension` of the suite struct rather than a new `@Suite`
/// on purpose — a second suite would run in parallel with the original and
/// race it for the single shared GGUF / Metal device. See
/// `.claude/rules/testing.md` § "Splitting a Suite Across Files".
/// Suite traits (`.serialized`, `.enabled(if:)`) are inherited from the
/// declaration in `LlamaCppIntegrationTests.swift`.
extension LlamaCppIntegrationTests {

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

    // Holdback check for the plaintext stop sentinel. Vacuous against Gemma 4
    // (this suite's model), whose vocabulary has no `<|im_end|>` — nothing here
    // constructs a delta that could carry it. Kept because the same suite shape
    // is reused when onboarding a ChatML model, where the sentinel is a form a
    // hallucination really does spell out. See #1417.
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
}
