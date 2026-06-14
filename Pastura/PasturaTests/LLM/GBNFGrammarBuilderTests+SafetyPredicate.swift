import Foundation
import Testing

@testable import Pastura

// Sibling-file split of GBNFGrammarBuilderTests (file_length 400-line cap).
// Extension, NOT a new @Suite — a separate suite would run in parallel and
// is not needed here (see .claude/rules/testing.md § "Splitting a Suite").
extension GBNFGrammarBuilderTests {
  @Test("isSafeEnumerationOption mirrors the builder's reject set")
  func isSafeEnumerationOptionMatchesValidation() {
    // The non-throwing predicate must agree with the throwing
    // `validateEnumerationOption` path so callers (e.g. VoteHandler) can
    // pre-filter dynamic enumeration values and fall back to `.string`
    // instead of triggering the `BuilderError.invalidEnumerationOption`
    // abort at sampler init (#524).
    let unsafe = ["has\"quote", "has\\backslash", "has\nnewline", "has\ttab"]
    for option in unsafe {
      #expect(
        !GBNFGrammarBuilder.isSafeEnumerationOption(option),
        "\(option.debugDescription) must be reported unsafe")
      // Cross-check: the throwing builder path rejects the same input.
      #expect(throws: GBNFGrammarBuilder.BuilderError.self) {
        try builder.build(
          from: OutputSchema(fields: [
            .init(name: "action", kind: .enumeration([option]))
          ]))
      }
    }

    // Safe: ASCII identifiers, names with spaces / apostrophes, and CJK
    // — all pass the predicate and the throwing builder accepts them.
    let safe = ["cooperate", "Alice", "O'Brien", "Mad Scientist", "開き直りマコ", "体験者ミラクル子"]
    for option in safe {
      #expect(
        GBNFGrammarBuilder.isSafeEnumerationOption(option),
        "\(option.debugDescription) must be reported safe")
    }
    // Empty string carries no hostile char, so the predicate reports safe;
    // empty *lists* are gated separately by the caller / `emptyEnumeration`.
    #expect(GBNFGrammarBuilder.isSafeEnumerationOption(""))
  }
}
