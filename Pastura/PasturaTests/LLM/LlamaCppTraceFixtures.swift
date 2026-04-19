import Foundation

@testable import Pastura

/// Synthetic llama.cpp trace fixtures covering the edge cases the partial
/// extractor must handle. Real device-captured traces can be added later
/// by running the app with `PASTURA_TRACE_LLM=1` and converting the
/// resulting JSON into additional factory methods here (or by loading
/// them as bundle resources once fixture volume justifies the project
/// plumbing).
enum LlamaCppTraceFixtures {
  enum LookupError: Error, Equatable {
    case notFound(name: String)
  }

  static func allSynthetic() -> [(name: String, fixture: LlamaCppTraceFixture)] {
    [
      ("normal_statement", normalStatement()),
      ("cjk_utf8_boundary", cjkUtf8Boundary()),
      ("escaped_quote", escapedQuote())
    ]
  }

  static func named(_ name: String) throws -> LlamaCppTraceFixture {
    guard let match = allSynthetic().first(where: { $0.name == name }) else {
      throw LookupError.notFound(name: name)
    }
    return match.fixture
  }

  // MARK: - Fixtures

  /// Clean happy-path trace: Gemma 4 channel-thinking preamble, then a
  /// JSON object with `statement` followed by `inner_thought`, then the
  /// chat-template end-of-turn marker. Pieces are aligned on natural
  /// character boundaries — no UTF-8 split, no escape-sequence split.
  private static func normalStatement() -> LlamaCppTraceFixture {
    let chunks = [
      "<|channel>thought\n",
      "I should cooperate.",
      "<channel|>",
      "{\"statement\":\"",
      "Let's cooperate.",
      "\",\"inner_thought\":\"",
      "Risky but worth trying.",
      "\"}",
      "<|im_end|>"
    ]
    return fixture(
      chunks: chunks, baseTokenId: 100,
      notes: "Happy-path trace — clean tokenization with char-aligned pieces."
    )
  }

  /// The `statement` value contains 「協力します」 where the first
  /// character 「協」 (0xE5 0x8D 0x94) is deliberately split 2+1 bytes
  /// across two adjacent pieces. The partial extractor must buffer the
  /// leading two bytes until the continuation arrives; emitting mid-char
  /// would surface a replacement character `?` in the UI.
  private static func cjkUtf8Boundary() -> LlamaCppTraceFixture {
    // 協力します in raw UTF-8 bytes.
    let japaneseBytes: [UInt8] = [
      0xE5, 0x8D, 0x94,  // 協
      0xE5, 0x8A, 0x9B,  // 力
      0xE3, 0x81, 0x97,  // し
      0xE3, 0x81, 0xBE,  // ま
      0xE3, 0x81, 0x99  // す
    ]
    let prefix = Data(#"{"statement":""#.utf8)
    let partialHead = Data(japaneseBytes[0..<2])  // 2 of 3 bytes of 協
    let continuation = Data(japaneseBytes[2..<japaneseBytes.count])
    let suffix = Data(#"","inner_thought":"plan"}"#.utf8)

    let pieces: [LlamaCppTraceFixture.Piece] = [
      .init(tokenId: 200, bytes: prefix),
      .init(tokenId: 201, bytes: partialHead),
      .init(tokenId: 202, bytes: continuation),
      .init(tokenId: 203, bytes: suffix)
    ]
    var finalBytes = Data()
    for piece in pieces { finalBytes.append(piece.bytes) }
    return LlamaCppTraceFixture(
      model: "synthetic", backend: "synthetic",
      system: commonSystem, user: commonUser,
      pieces: pieces,
      finalText: String(data: finalBytes, encoding: .utf8) ?? "",
      completionTokens: pieces.count,
      notes: "UTF-8 boundary — 「協」 split 2+1 bytes across pieces 201 and 202."
    )
  }

  /// A JSON string value containing an escaped quote `\"`. The extractor
  /// must track string-escape state rather than naively terminating the
  /// primary value at the first `"` it sees.
  private static func escapedQuote() -> LlamaCppTraceFixture {
    let chunks = [
      #"{"statement":""#,
      #"She said "#,
      #"\"hi\" "#,
      #"loudly."#,
      #"","inner_thought":"ok"}"#
    ]
    return fixture(
      chunks: chunks, baseTokenId: 300,
      notes: #"Escape sequence — \" inside a string value."#
    )
  }

  // MARK: - Helpers

  private static let commonSystem = "You are a test agent."
  private static let commonUser = "Give a cooperative response in JSON."

  /// Build a fixture from UTF-8 chunks. Each chunk becomes one piece.
  /// Use this when no byte-boundary split is required — UTF-8 / escape
  /// edge cases construct their `Piece` arrays manually.
  private static func fixture(
    chunks: [String], baseTokenId: Int, notes: String
  ) -> LlamaCppTraceFixture {
    let pieces = chunks.enumerated().map { idx, chunk in
      LlamaCppTraceFixture.Piece(
        tokenId: baseTokenId + idx, bytes: Data(chunk.utf8))
    }
    let finalText = chunks.joined()
    return LlamaCppTraceFixture(
      model: "synthetic", backend: "synthetic",
      system: commonSystem, user: commonUser,
      pieces: pieces,
      finalText: finalText,
      completionTokens: pieces.count,
      notes: notes
    )
  }
}
