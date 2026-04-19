import Foundation

/// On-disk schema for a captured llama.cpp inference trace.
///
/// Test fixtures under `PasturaTests/LLM/LlamaCppTraceFixtures.swift` and
/// traces written by `LlamaCppService` (DEBUG builds with the
/// `PASTURA_TRACE_LLM` environment variable set) share this shape so that
/// a fixture captured from a real device is directly consumable by
/// `PartialOutputExtractor` tests without format conversion.
///
/// Raw bytes are base64-encoded rather than stored as UTF-8 strings so
/// that a piece containing a partial UTF-8 sequence — which happens when
/// llama.cpp splits a multi-byte character across two adjacent token
/// pieces — is preserved exactly. Reconstructing the full text is
/// therefore `concat(allPieces.bytes)` decoded as UTF-8, never per-piece.
nonisolated struct LlamaCppTraceFixture: Codable, Sendable, Equatable {
  static let currentSchema = "pastura-llm-trace/v1"

  let schema: String
  let model: String
  let backend: String
  let system: String
  let user: String
  let pieces: [Piece]
  let finalText: String
  let completionTokens: Int?
  let notes: String?

  nonisolated struct Piece: Codable, Sendable, Equatable {
    /// llama.cpp's internal token ID for this piece. Informational only —
    /// tests do not rely on specific ID values because IDs are
    /// tokenizer-version-specific.
    let tokenId: Int
    /// Base64-encoded raw bytes emitted by `llama_token_to_piece`.
    let b64: String

    init(tokenId: Int, bytes: Data) {
      self.tokenId = tokenId
      self.b64 = bytes.base64EncodedString()
    }

    init(tokenId: Int, b64: String) {
      self.tokenId = tokenId
      self.b64 = b64
    }

    /// The raw bytes this piece represents. Empty `Data()` for malformed
    /// base64 — loader tests flag this as an authoring error rather than
    /// letting it silently propagate into downstream extractor tests.
    var bytes: Data { Data(base64Encoded: b64) ?? Data() }
  }

  init(
    schema: String = currentSchema,
    model: String,
    backend: String,
    system: String,
    user: String,
    pieces: [Piece],
    finalText: String,
    completionTokens: Int?,
    notes: String? = nil
  ) {
    self.schema = schema
    self.model = model
    self.backend = backend
    self.system = system
    self.user = user
    self.pieces = pieces
    self.finalText = finalText
    self.completionTokens = completionTokens
    self.notes = notes
  }
}
