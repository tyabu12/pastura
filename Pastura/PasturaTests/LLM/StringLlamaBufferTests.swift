import Testing

@testable import Pastura

/// Unit tests for the `String(llamaBuffer:length:)` initializer that
/// replaces deprecated `String(cString:)` at llama.cpp call sites.
@Suite(.timeLimit(.minutes(1)))
struct StringLlamaBufferTests {

  // MARK: - Happy path

  @Test func decodesValidUTF8UpToExplicitLength() {
    // Buffer: "hello" + trailing garbage past length
    var buffer = [CChar](repeating: 0, count: 16)
    let utf8: [CChar] = [0x68, 0x65, 0x6C, 0x6C, 0x6F]  // "hello"
    for (index, byte) in utf8.enumerated() { buffer[index] = byte }
    buffer[5] = 0x21  // '!' past the length boundary — must NOT be decoded

    let result = String(llamaBuffer: buffer, length: 5)
    #expect(result == "hello")
  }

  @Test func lengthEqualToBufferCountDecodesEntireBuffer() {
    let utf8: [CChar] = [0x61, 0x62, 0x63]  // "abc"
    let result = String(llamaBuffer: utf8, length: utf8.count)
    #expect(result == "abc")
  }

  // MARK: - Multi-byte UTF-8

  @Test func decodesMultiByteUTF8() {
    // "あ" = U+3042 = 0xE3 0x81 0x82 in UTF-8 (3 bytes).
    // CChar is Int8; bytes ≥ 0x80 must be cast via bitPattern.
    let utf8: [CChar] = [
      CChar(bitPattern: 0xE3),
      CChar(bitPattern: 0x81),
      CChar(bitPattern: 0x82)
    ]
    let result = String(llamaBuffer: utf8, length: 3)
    #expect(result == "あ")
  }

  // MARK: - Edge cases

  @Test func zeroLengthReturnsEmptyString() {
    let buffer: [CChar] = [0x68, 0x65, 0x6C, 0x6C, 0x6F]
    let result = String(llamaBuffer: buffer, length: 0)
    #expect(result == "")
  }

  @Test func emptyBufferReturnsEmptyString() {
    let result = String(llamaBuffer: [], length: 0)
    #expect(result == "")
  }

  // MARK: - Invalid UTF-8

  @Test func invalidUTF8ReturnsEmptyString() {
    // 0xFF is invalid as the leading byte of any UTF-8 sequence.
    // Documents the contract change vs `String(cString:)` (which would
    // substitute U+FFFD); we choose `""` over partial / repaired output.
    let buffer: [CChar] = [
      CChar(bitPattern: 0x68),  // 'h'
      CChar(bitPattern: 0xFF),  // invalid
      CChar(bitPattern: 0x69)  // 'i'
    ]
    let result = String(llamaBuffer: buffer, length: 3)
    #expect(result == "")
  }
}
