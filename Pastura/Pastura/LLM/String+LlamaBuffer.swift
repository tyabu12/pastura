import Foundation

// MARK: - String + Llama buffer decoding

extension String {
  /// Decodes a UTF-8 byte sequence from a `[CChar]` buffer of known length.
  ///
  /// Replaces deprecated `String(cString:)` for cases where the C function
  /// returned an explicit byte count (e.g., `llama_tokenize`,
  /// `llama_chat_apply_template`, `llama_token_to_piece`).
  ///
  /// Uses `String(bytes:encoding:)` on the `Int8` slice reinterpreted as
  /// `UInt8`, which is valid on iOS 17+ (unlike `String(validating:as:)`,
  /// which requires iOS 18).
  ///
  /// **Behavior on invalid UTF-8**: returns an empty string. This differs
  /// from `String(cString:)` which substitutes `U+FFFD` for invalid bytes.
  /// For Pastura, this is acceptable because the strict byte-stream path
  /// uses `decodePieceRaw` (which preserves raw bytes); the lossy
  /// `decodePiece` path was already documented as best-effort.
  nonisolated init(llamaBuffer buffer: [CChar], length: Int) {
    // Reinterpret Int8 as UInt8 — the bit pattern is identical; only the
    // signed vs unsigned interpretation differs. String(bytes:encoding:)
    // treats the sequence as raw UTF-8 bytes and returns nil for invalid input.
    let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
    self = String(bytes: bytes, encoding: .utf8) ?? ""
  }
}
