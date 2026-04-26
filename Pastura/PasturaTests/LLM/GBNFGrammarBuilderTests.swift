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

  @Test("root rule ends with trailing rule + trailing rule is defined")
  func rootEndsWithPermissiveTrailing() throws {
    // Regression guard for the llama.cpp `accept_token` crash:
    //   std::runtime_error("Unexpected empty grammar stack after accepting piece: …")
    // Three TestFlight rounds bit us en route to the current shape:
    //   1. root ending at `"}"` exactly → crash on any post-`}` token
    //   2. root ending at `"}" ws` → crash on BPE-merged tokens like
    //      `}: ` (7493) where the tail is non-whitespace
    //   3. root ending at `"}" [^\x00]*` / `"}" [^"\\]*` →
    //      `init_grammar` returned NULL at parse time (top-level
    //      Kleene star on a char class seems to trip llama.cpp's
    //      grammar parser — same symptom as `ws ::= [ \t\n]*`).
    // Final shape: `"}" trailing` with `trailing ::= ([^"\\] trailing)?`
    // — recursive form parses cleanly AND accepts arbitrary trailing
    // bytes. See in-code comments on `rootRule` and
    // `sharedTrailingProduction` for the full rationale.
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    let rootLine = grammar.components(separatedBy: "\n").first { $0.hasPrefix("root ::=") } ?? ""
    #expect(
      rootLine.hasSuffix(#""}" trailing"#),
      "root must end with trailing rule reference, got: \(rootLine)")
    // Trailing rule must itself be defined in the grammar with the
    // positive-class recursive form (negation + recursion triggered
    // parse-time NULL — see rationale in `sharedTrailingProduction`).
    #expect(
      grammar.contains(#"trailing ::= ([\t\n\r -~] trailing)?"#),
      "grammar must define `trailing` in recursive + positive-class form")
  }

  @Test("ws production allows space / tab / newline (recursive form)")
  func whitespaceProductionIsPermissive() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    // Matches llama.cpp's official json.gbnf recursive form — see the
    // in-code comment on `sharedWhitespaceProduction` for the history.
    #expect(grammar.contains(#"ws ::= ([ \t\n] ws)?"#))
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
        #"root ::= "{" ws "\"statement\"" ws ":" ws string ws "}" trailing"#))
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
        #"root ::= "{" ws "\"statement\"" ws ":" ws string ws "," ws "\"inner_thought\"" ws ":" ws string ws "}" trailing"#
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
      grammar.contains(#"root ::= "{" ws "\"action\"" ws ":" ws action-value ws "}" trailing"#))
    #expect(
      grammar.contains(#"action-value ::= "\"cooperate\"" | "\"betray\"""#))
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
    #expect(grammar.contains(#"action-value ::= "\"cooperate\"" | "\"betray\"""#))
    #expect(
      grammar.contains(
        #"root ::= "{" ws "\"action\"" ws ":" ws action-value ws "," ws "\"inner_thought\"" ws ":" ws string ws "}" trailing"#
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
    // Pastura preset field-name input requires a leading letter
    // followed by letter / digit / `_`. The actual GBNF rule shape
    // (no `_`) is enforced separately by `sanitizeRuleName` at emit
    // time, so `dash-only` is rejected here as Pastura input
    // convention. Leading `_` is now also rejected — sanitization
    // would produce a leading-`-` rule identifier (`-thing-value`)
    // which is unconventional and a future llama.cpp tightening
    // could reject (ADR-002 §12.8). Leading digit / literal `.` /
    // spaces fail in any case.
    let badNames = [
      "1badName", "with space", "dash-only", "dot.name",
      "_leading", "-leading",
      // Edge cases adjacent to the leading-letter rule:
      "",  // empty — no first char to validate
      "_",  // single leading non-letter
      "-"  // same, dash form
    ]
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

  @Test("valid field names accepted (ASCII snake_case + Unicode letters)")
  func validFieldNamesAccepted() throws {
    // `validateFieldName` is Unicode-aware via `Character.isLetter`:
    // ASCII snake_case (`_` only in body, never leading) AND non-ASCII
    // letters like Japanese both pass. The Unicode case would surface
    // as an `is_word_char` mismatch at llama.cpp's emit time (deferred
    // per ADR-002 §12.8); the stderr-capture diagnostic in
    // `+Sampler.swift` would catch it within one device run. This
    // test locks in the builder-level Unicode acceptance so a future
    // contributor tightening to ASCII-only must break it explicitly.
    let okNames = [
      "statement", "inner_thought", "action", "a1b2", "内なる思考"
    ]
    for name in okNames {
      let schema = OutputSchema(fields: [.init(name: name, kind: .string)])
      _ = try builder.build(from: schema)
    }
  }

  @Test("enum field name with `_` emits sanitized `-` rule reference")
  func enumFieldNameUnderscoreSanitizedToHyphenInRuleName() throws {
    // `is_word_char` (llama-grammar.cpp:98 of b8694) rejects `_` in rule
    // identifiers, so Pastura snake_case input gets mapped to hyphenated
    // form at emit time. JSON keys (which appear inside string literals)
    // are unaffected and retain the original `_`.
    let schema = OutputSchema(fields: [
      .init(name: "inner_secret", kind: .enumeration(["alpha", "beta"]))
    ])
    let grammar = try builder.build(from: schema)
    // Rule reference and definition both use the sanitized form.
    #expect(grammar.contains("inner-secret-value"))
    #expect(!grammar.contains("inner_secret-value"))
    #expect(!grammar.contains("inner_secret_value"))
    // JSON key inside the string literal keeps the original `_`.
    #expect(grammar.contains(#""\"inner_secret\"""#))
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
    #expect(grammar.contains(#"action-value ::= "\"協力\"" | "\"裏切り\"""#))
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
    ws ::= ([ \\t\\n] ws)?
    trailing ::= ([\\t\\n\\r -~] trailing)?
    """

  private static let goldenChooseActionBetray = """
    root ::= "{" ws "\\"action\\"" ws ":" ws action-value ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}" trailing
    action-value ::= "\\"cooperate\\"" | "\\"betray\\""
    \(sharedTail)
    """

  private static let goldenDeclarationInnerThought = """
    root ::= "{" ws "\\"declaration\\"" ws ":" ws string ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}" trailing
    \(sharedTail)
    """

  private static let goldenStatementInnerThought = """
    root ::= "{" ws "\\"statement\\"" ws ":" ws string ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}" trailing
    \(sharedTail)
    """

  private static let goldenVoteReason = """
    root ::= "{" ws "\\"vote\\"" ws ":" ws string ws "," ws "\\"reason\\"" ws ":" ws string ws "}" trailing
    \(sharedTail)
    """
}
