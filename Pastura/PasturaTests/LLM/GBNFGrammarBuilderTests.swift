import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct GBNFGrammarBuilderTests {
  let builder = GBNFGrammarBuilder()

  // MARK: - Shared productions (must appear in every generated grammar)

  @Test("string production accepts UTF-8 via `[^\"\\\\]`")
  func stringProductionAcceptsUTF8() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    // The byte-class `[^"\\]` accepts any byte that is not `"` or `\`,
    // which includes all non-ASCII UTF-8 continuation / lead bytes —
    // Japanese / emoji pass through transparently.
    #expect(grammar.contains(#"[^"\\]"#))
    // All six non-`"` / non-`\` single-char escapes the JSON spec
    // requires must be reachable in the escape branch.
    #expect(grammar.contains(#"["\\/bfnrt]"#))
    // 4-hex unicode escape must be present for `\uXXXX` forms.
    #expect(grammar.contains("[0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]"))
  }

  @Test("ws production allows space / tab / newline")
  func whitespaceProductionIsPermissive() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    #expect(grammar.contains(#"ws ::= [ \t\n]*"#))
  }

  // MARK: - Field shapes

  @Test("single string field: root references shared string production")
  func singleStringField() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    #expect(
      grammar.contains(
        #"root ::= "{" ws "\"statement\"" ws ":" ws string ws "}""#))
  }

  @Test("multi-field root joins with `ws \",\" ws`")
  func multiStringFields() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string),
      .init(name: "inner_thought", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    #expect(
      grammar.contains(
        #"root ::= "{" ws "\"statement\"" ws ":" ws string ws "," ws "\"inner_thought\"" ws ":" ws string ws "}""#
      ))
  }

  @Test("three fields preserve primary-first OutputSchema order")
  func threeFieldOrderPreserved() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string),
      .init(name: "inner_thought", kind: .string),
      .init(name: "extra", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    // The root production must list fields in OutputSchema.fields order,
    // not sorted — sorting would invert primary-first, critical invariant.
    guard
      let sIdx = grammar.range(of: #""\"statement\"""#)?.lowerBound,
      let iIdx = grammar.range(of: #""\"inner_thought\"""#)?.lowerBound,
      let eIdx = grammar.range(of: #""\"extra\"""#)?.lowerBound
    else {
      Issue.record("expected all three field literals in grammar")
      return
    }
    #expect(sIdx < iIdx)
    #expect(iIdx < eIdx)
  }

  // MARK: - Enumeration (choose.options)

  @Test("enumeration generates a per-field alternation rule")
  func enumerationAloneProducesPerFieldRule() throws {
    let schema = OutputSchema(fields: [
      .init(name: "action", kind: .enumeration(["cooperate", "betray"]))
    ])
    let grammar = try builder.build(from: schema)
    #expect(
      grammar.contains(#"root ::= "{" ws "\"action\"" ws ":" ws action_value ws "}""#))
    #expect(
      grammar.contains(#"action_value ::= "\"cooperate\"" | "\"betray\"""#))
    // Enumeration-only grammars still include `string` + `ws` because
    // shared productions are emitted unconditionally (cheap; avoids
    // future regression if an enumeration grammar later references them).
    #expect(grammar.contains("string ::="))
    #expect(grammar.contains("ws ::="))
  }

  @Test("enumeration + string mix: enumeration rule AND string production")
  func enumerationMixedWithString() throws {
    // prisoners_dilemma choose-phase shape — covered in golden-file test
    // below too, but kept here as a focused per-field assertion.
    let schema = OutputSchema(fields: [
      .init(name: "action", kind: .enumeration(["cooperate", "betray"])),
      .init(name: "inner_thought", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    #expect(grammar.contains(#"action_value ::= "\"cooperate\"" | "\"betray\"""#))
    #expect(
      grammar.contains(
        #"root ::= "{" ws "\"action\"" ws ":" ws action_value ws "," ws "\"inner_thought\"" ws ":" ws string ws "}""#
      ))
  }

  // MARK: - Validation errors

  @Test("empty enumeration throws")
  func emptyEnumerationThrows() {
    let schema = OutputSchema(fields: [
      .init(name: "action", kind: .enumeration([]))
    ])
    #expect(throws: GBNFGrammarBuilder.BuilderError.self) {
      try builder.build(from: schema)
    }
  }

  @Test("duplicate field name throws")
  func duplicateFieldNameThrows() {
    // OutputSchema.from(phase:) can't produce this (dictionary uniqueness),
    // but direct construction allows it — defensive builder-side guard.
    let schema = OutputSchema(fields: [
      .init(name: "a", kind: .string),
      .init(name: "a", kind: .string)
    ])
    #expect(throws: GBNFGrammarBuilder.BuilderError.self) {
      try builder.build(from: schema)
    }
  }

  @Test("invalid rule-name field throws")
  func invalidFieldNameThrows() {
    // GBNF rule names must match [a-zA-Z_][a-zA-Z0-9_-]* — a leading digit
    // or a literal `.` would produce unparseable grammar at llama.cpp's end.
    let badNames = ["1badName", "with space", "dash-only", "dot.name"]
    for name in badNames {
      let schema = OutputSchema(fields: [.init(name: name, kind: .string)])
      #expect(
        throws: GBNFGrammarBuilder.BuilderError.self,
        "\(name) should be rejected"
      ) {
        try builder.build(from: schema)
      }
    }
  }

  @Test("valid snake_case field names accepted")
  func validSnakeCaseNamesAccepted() throws {
    let okNames = ["statement", "inner_thought", "action", "_private", "a1b2"]
    for name in okNames {
      let schema = OutputSchema(fields: [.init(name: name, kind: .string)])
      _ = try builder.build(from: schema)
    }
  }

  @Test("enumeration options with GBNF-hostile chars throw")
  func enumerationOptionWithHostileCharsThrows() {
    // Share Board scenarios can inject arbitrary option strings; the
    // builder validates upfront so failures surface as a clear
    // BuilderError rather than a NULL-return from llama.cpp's grammar
    // parser (which would hit `LLMError.invalidGrammar` at sampler init).
    let badOptions: [String] = [
      "has\"quote",  // raw `"` would break the GBNF literal
      "has\\backslash",  // `\` would need escaping
      "has\nnewline",  // control byte
      "has\ttab"  // control byte
    ]
    for option in badOptions {
      let schema = OutputSchema(fields: [
        .init(name: "action", kind: .enumeration([option]))
      ])
      #expect(
        throws: GBNFGrammarBuilder.BuilderError.self,
        "option \(option.debugDescription) should be rejected"
      ) {
        try builder.build(from: schema)
      }
    }
  }

  @Test("enumeration options with CJK / unicode accepted")
  func enumerationOptionWithUnicodeAccepted() throws {
    // Non-ASCII printable characters are fine — GBNF's `[^"\\]` byte
    // class accepts them transparently and they don't collide with
    // literal delimiters.
    let schema = OutputSchema(fields: [
      .init(name: "action", kind: .enumeration(["協力", "裏切り"]))
    ])
    let grammar = try builder.build(from: schema)
    #expect(grammar.contains(#"action_value ::= "\"協力\"" | "\"裏切り\"""#))
  }

  // MARK: - Golden files (each preset LLM phase)

  // CI-runnable: these byte-for-byte comparisons catch silent drift
  // between the grammar the builder produces and what the measurement
  // protocol exercises on device. If a future change to `GBNFGrammarBuilder`
  // or `OutputSchema.from(phase:)` reorders fields or rewrites a
  // production, these tests fail FAST at the highest level CI can
  // reach — pairs with the opt-in on-device LlamaCppGrammarTests in Item 4.

  @Test("golden: prisoners_dilemma choose phase")
  func goldenPrisonersDilemmaChoose() throws {
    let phase = Phase(
      type: .choose, prompt: "…",
      outputSchema: ["action": "string", "inner_thought": "string"],
      options: ["cooperate", "betray"])
    let schema = try #require(OutputSchema.from(phase: phase))
    let grammar = try builder.build(from: schema)
    #expect(grammar == Self.goldenChooseActionBetray)
  }

  @Test("golden: prisoners_dilemma speak_all phase")
  func goldenPrisonersDilemmaSpeakAll() throws {
    let phase = Phase(
      type: .speakAll, prompt: "…",
      outputSchema: ["declaration": "string", "inner_thought": "string"])
    let schema = try #require(OutputSchema.from(phase: phase))
    let grammar = try builder.build(from: schema)
    #expect(grammar == Self.goldenDeclarationInnerThought)
  }

  @Test("golden: word_wolf speak_all phase")
  func goldenWordWolfSpeakAll() throws {
    let phase = Phase(
      type: .speakAll, prompt: "…",
      outputSchema: ["statement": "string", "inner_thought": "string"])
    let schema = try #require(OutputSchema.from(phase: phase))
    let grammar = try builder.build(from: schema)
    #expect(grammar == Self.goldenStatementInnerThought)
  }

  @Test("golden: word_wolf vote phase")
  func goldenWordWolfVote() throws {
    let phase = Phase(
      type: .vote, prompt: "…",
      outputSchema: ["vote": "string", "reason": "string"])
    let schema = try #require(OutputSchema.from(phase: phase))
    let grammar = try builder.build(from: schema)
    #expect(grammar == Self.goldenVoteReason)
  }

  // MARK: - Golden file constants

  private static let sharedTail = """
    string ::= "\\"" ( [^"\\\\] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) )* "\\""
    ws ::= [ \\t\\n]*
    """

  private static let goldenChooseActionBetray = """
    root ::= "{" ws "\\"action\\"" ws ":" ws action_value ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}"
    action_value ::= "\\"cooperate\\"" | "\\"betray\\""
    \(sharedTail)
    """

  private static let goldenDeclarationInnerThought = """
    root ::= "{" ws "\\"declaration\\"" ws ":" ws string ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}"
    \(sharedTail)
    """

  private static let goldenStatementInnerThought = """
    root ::= "{" ws "\\"statement\\"" ws ":" ws string ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}"
    \(sharedTail)
    """

  private static let goldenVoteReason = """
    root ::= "{" ws "\\"vote\\"" ws ":" ws string ws "," ws "\\"reason\\"" ws ":" ws string ws "}"
    \(sharedTail)
    """
}
