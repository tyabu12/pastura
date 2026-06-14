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

  // MARK: - Choice fields use the shared string production

  @Test("choice field is grammar-equivalent to string (no value enumeration)")
  func choiceFieldUsesStringProduction() throws {
    // `.choice` carries no option payload — the grammar must NOT enumerate
    // values (model-agnostic crash safety, #599). The action value position
    // references the shared `string` production, exactly like a `.string`
    // field, and no `action-value` alternation rule is emitted.
    let schema = OutputSchema(fields: [
      .init(name: "action", kind: .choice),
      .init(name: "inner_thought", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    #expect(
      grammar.contains(
        #"root ::= "{" ws "\"action\"" ws ":" ws string ws "," ws "\"inner_thought\"" ws ":" ws string ws "}" trailing"#
      ))
    // No per-field enumeration rule is emitted for the choice field.
    // (The shared `string` production legitimately contains ` | ` for the
    // JSON escape alternation, so we assert on the rule name, not ` | `.)
    #expect(!grammar.contains("action-value"))
  }

  // MARK: - Validation errors

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

  @Test("invalid field name throws")
  func invalidFieldNameThrows() {
    // Field names are emitted as JSON-key literals (`"\"name\""`) in the
    // grammar. Pastura input requires a leading letter followed by
    // letter / digit / `_`. Leading `_` / `-` stay rejected as a
    // conservative hygiene rule (originally also guarded the now-removed
    // `<name>-value` rule identifier — ADR-002 §12.8, historical).
    // Leading digit / literal `.` / spaces fail in any case.
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
    // letters like Japanese both pass at the builder level. This test
    // locks in builder-level Unicode acceptance so a future contributor
    // tightening to ASCII-only must break it explicitly. (Non-ASCII
    // field NAMES become JSON-key literals; a CJK-key on-device crash is
    // the same mechanism as the removed CJK-option crash and is tracked
    // as a separate follow-up — out of scope for #599, which covers
    // choose OPTION values.)
    let okNames = [
      "statement", "inner_thought", "action", "a1b2", "内なる思考"
    ]
    for name in okNames {
      let schema = OutputSchema(fields: [.init(name: name, kind: .string)])
      _ = try builder.build(from: schema)
    }
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
    #expect(grammar == Self.goldenChooseAction)
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

  // Regression guard for issue #334: minimal single-field `{statement: string}`
  // schemas — the shape that historically triggered an uncaught C++ exception
  // in `llama_grammar_accept_token` at runtime. Multi-field grammars above are
  // already byte-for-byte locked; without an equivalent single-field golden, a
  // future builder change could regress only the single-field path and remain
  // undetected until on-device repro.
  @Test("golden: minimal single-field statement (issue #334 repro shape)")
  func goldenSingleFieldStatement() throws {
    let phase = Phase(
      type: .speakAll, prompt: "…",
      outputSchema: ["statement": "string"])
    let schema = try #require(OutputSchema.from(phase: phase))
    let grammar = try builder.build(from: schema)
    #expect(grammar == Self.goldenSingleStatement)
  }

  // MARK: - Golden file constants

  private static let sharedTail = """
    string ::= "\\"" ( [^"\\\\] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) )* "\\""
    ws ::= ([ \\t\\n] ws)?
    trailing ::= ([\\t\\n\\r -~] trailing)?
    """

  // Choose phase: `action` is a `.choice` field, grammar-equivalent to
  // `.string` (no value enumeration — #599). Shape matches a two-string
  // schema with `action` + `inner_thought` keys.
  private static let goldenChooseAction = """
    root ::= "{" ws "\\"action\\"" ws ":" ws string ws "," ws "\\"inner_thought\\"" ws ":" ws string ws "}" trailing
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

  private static let goldenSingleStatement = """
    root ::= "{" ws "\\"statement\\"" ws ":" ws string ws "}" trailing
    \(sharedTail)
    """
}
