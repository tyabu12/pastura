import Foundation
import Testing

@testable import Pastura

struct LlamaCppTraceFixtureTests {

  // MARK: - Round-trip

  @Test func encodesAndDecodesRoundTrip() throws {
    let original = LlamaCppTraceFixture(
      model: "test-model",
      backend: "test-backend",
      system: "sys",
      user: "usr",
      pieces: [
        .init(tokenId: 1, bytes: Data([0x48, 0x69])),
        .init(tokenId: 2, bytes: Data([0x21]))
      ],
      finalText: "Hi!",
      completionTokens: 2
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(LlamaCppTraceFixture.self, from: data)
    #expect(decoded == original)
    #expect(decoded.pieces[0].bytes == Data([0x48, 0x69]))
  }

  @Test func emptyPieceRoundTrips() throws {
    let piece = LlamaCppTraceFixture.Piece(tokenId: 0, bytes: Data())
    let data = try JSONEncoder().encode(piece)
    let decoded = try JSONDecoder().decode(LlamaCppTraceFixture.Piece.self, from: data)
    #expect(decoded.bytes == Data())
  }

  // MARK: - Schema stamp

  @Test func syntheticFixturesUseCurrentSchema() throws {
    for (name, fixture) in LlamaCppTraceFixtures.allSynthetic() {
      #expect(
        fixture.schema == LlamaCppTraceFixture.currentSchema,
        "fixture \(name) has wrong schema")
    }
  }

  // MARK: - Reconstruction invariant
  //
  // For every synthetic fixture, concatenating all piece bytes and decoding
  // as UTF-8 must equal `finalText`. This is the property that makes
  // fixtures safe to replay byte-by-byte into the partial extractor (item
  // 5): feeding bytes[0..<n] for any prefix length n must yield a state
  // consistent with parsing `finalText[0..<chars(n)]`.

  @Test func syntheticFixturesReconstructFinalText() throws {
    for (name, fixture) in LlamaCppTraceFixtures.allSynthetic() {
      var bytes = Data()
      for piece in fixture.pieces { bytes.append(piece.bytes) }
      let reconstructed = String(data: bytes, encoding: .utf8)
      #expect(
        reconstructed == fixture.finalText,
        "fixture \(name) reconstruction mismatch")
    }
  }

  // MARK: - Edge-case property tags

  @Test func cjkBoundaryFixtureContainsPartialUtf8Piece() throws {
    let fixture = try LlamaCppTraceFixtures.named("cjk_utf8_boundary")
    // At least one piece on its own must NOT be valid UTF-8 — that is
    // exactly the condition the partial extractor has to handle.
    let hasPartial = fixture.pieces.contains { piece in
      !piece.bytes.isEmpty && String(data: piece.bytes, encoding: .utf8) == nil
    }
    #expect(
      hasPartial,
      "cjk_utf8_boundary fixture must include at least one piece with a partial UTF-8 sequence"
    )
  }

  @Test func escapedQuoteFixtureContainsBackslashQuote() throws {
    let fixture = try LlamaCppTraceFixtures.named("escaped_quote")
    #expect(fixture.finalText.contains(#"\""#))
  }

  // MARK: - Lookup

  @Test func namedLookupMissesThrow() {
    #expect(throws: LlamaCppTraceFixtures.LookupError.self) {
      _ = try LlamaCppTraceFixtures.named("does_not_exist")
    }
  }
}
