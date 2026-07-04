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
    // Final shape: `"}" trailing` with a BOUNDED chain
    // `trailing ::= ([\t\n\r -~] trailing1)?` … `trailing15 ::= ([\t\n\r -~])?`
    // — recursive positive-class form parses cleanly AND caps trailing
    // bytes at 16 so the model can't emit unbounded fabricated follow-on
    // objects (#907). See in-code comments on `rootRule` and
    // `sharedTrailingProduction` for the full rationale.
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    let rootLine = grammar.components(separatedBy: "\n").first { $0.hasPrefix("root ::=") } ?? ""
    #expect(
      rootLine.hasSuffix(#""}" trailing"#),
      "root must end with trailing rule reference, got: \(rootLine)")
    // The head link references `trailing1` (bounded chain), NOT itself —
    // the unbounded self-reference invited fabricated follow-on objects.
    #expect(
      grammar.contains(#"trailing ::= ([\t\n\r -~] trailing1)?"#),
      "grammar must define `trailing` as the head of a bounded chain")
    #expect(
      !grammar.contains(#"trailing ::= ([\t\n\r -~] trailing)?"#),
      "grammar must NOT contain the unbounded self-referential trailing rule")
  }

  @Test("trailing chain is bounded to 16 links, terminal link has no self-ref")
  func trailingChainIsBounded() throws {
    let schema = OutputSchema(fields: [
      .init(name: "statement", kind: .string)
    ])
    let grammar = try builder.build(from: schema)
    let trailingRules = grammar.components(separatedBy: "\n")
      .filter { $0.hasPrefix("trailing") && $0.contains("::=") }
    // 16 rules total: `trailing` head + `trailing1` … `trailing15`.
    #expect(trailingRules.count == 16, "expected 16 trailing rules, got \(trailingRules.count)")
    // Terminal link caps the recursion — accepts one byte, references nothing.
    #expect(
      grammar.contains(#"trailing15 ::= ([\t\n\r -~])?"#),
      "terminal link `trailing15` must have no self/next reference")
    // No trailing rule references a `trailing16` (off-by-one guard).
    #expect(!grammar.contains("trailing16"))
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

  @Test("regression #599: CJK / GBNF-hostile choose options never reach the grammar as literals")
  func chooseOptionsNeverEnumeratedIntoGrammar() throws {
    // Replaces the former `enumerationOptionWithUnicodeAccepted` test,
    // which asserted CJK options were "fine" to enumerate. They were NOT:
    // CJK option literals crashed llama.cpp's sampler on-device
    // (token-dependent, uncatchable), and GBNF-hostile chars aborted the
    // run at sampler init. Both are now structurally impossible — choose
    // options become a payload-free `.choice` marker (no value
    // enumeration). This exercises the real `OutputSchema.from(phase:)` →
    // `build` path with dangerous options and asserts none leak into the
    // grammar and nothing throws. Reverting the `.choice` pivot fails this:
    // the literals would reappear (CJK) or `build` would throw (hostile).
    let dangerousOptions = ["協力", "裏切り", #"a"b"#, #"x\y"#, "with\nnewline"]
    let phase = Phase(
      type: .choose, prompt: "…",
      outputSchema: ["action": "string"],
      options: dangerousOptions)
    let schema = try #require(OutputSchema.from(phase: phase))
    #expect(schema.fields.first { $0.name == "action" }?.kind == .choice)
    // Must not throw — the dangerous options never reach a literal emitter.
    let grammar = try builder.build(from: schema)
    // The action value position references the shared `string` production.
    #expect(
      grammar.contains(#"root ::= "{" ws "\"action\"" ws ":" ws string ws "}" trailing"#))
    #expect(!grammar.contains("action-value"))
    // None of the option strings leaked into the grammar as literals.
    for option in dangerousOptions {
      #expect(
        !grammar.contains(option),
        "option \(option.debugDescription) must not appear in the grammar")
    }
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
    // grammar. Pastura input requires a leading ASCII letter followed by
    // ASCII letter / digit / `_` (`ScenarioConventions.isValidFieldName`).
    // Leading `_` / `-` stay rejected as a conservative hygiene rule;
    // leading digit / literal `.` / spaces fail in any case.
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

  @Test("regression #607: CJK / non-ASCII field NAMES are rejected at the builder")
  func nonAsciiFieldNamesRejected() {
    // #607: a CJK / multi-byte field NAME would emit as a JSON-key literal
    // (`"\"内なる思考\""`) and crash llama.cpp's sampler at accept-time
    // on-device — the same "empty grammar stack" mechanism that forced CJK
    // choose OPTION values out of the grammar in #599. The builder is the
    // unconditional crash backstop (some paths bypass `ScenarioValidator`),
    // so non-ASCII keys MUST throw here even though string VALUES stay
    // UTF-8-transparent (see `stringProductionAcceptsUTF8`).
    let hostileNames = ["内なる思考", "思考", "naïve", "café", "emoji😀key"]
    for name in hostileNames {
      let schema = OutputSchema(fields: [.init(name: name, kind: .string)])
      #expect(
        throws: GBNFGrammarBuilder.BuilderError.self,
        "\(name) should be rejected"
      ) {
        try builder.build(from: schema)
      }
    }
  }

  @Test("valid ASCII-identifier field names accepted")
  func validFieldNamesAccepted() throws {
    // `validateFieldName` delegates to `ScenarioConventions.isValidFieldName`:
    // ASCII snake_case (`_` only in body, never leading) plus trailing digits.
    // Non-ASCII letters are NOT accepted — see `nonAsciiFieldNamesRejected`
    // (#607).
    let okNames = ["statement", "inner_thought", "action", "vote", "reason", "a1b2"]
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
    trailing ::= ([\\t\\n\\r -~] trailing1)?
    trailing1 ::= ([\\t\\n\\r -~] trailing2)?
    trailing2 ::= ([\\t\\n\\r -~] trailing3)?
    trailing3 ::= ([\\t\\n\\r -~] trailing4)?
    trailing4 ::= ([\\t\\n\\r -~] trailing5)?
    trailing5 ::= ([\\t\\n\\r -~] trailing6)?
    trailing6 ::= ([\\t\\n\\r -~] trailing7)?
    trailing7 ::= ([\\t\\n\\r -~] trailing8)?
    trailing8 ::= ([\\t\\n\\r -~] trailing9)?
    trailing9 ::= ([\\t\\n\\r -~] trailing10)?
    trailing10 ::= ([\\t\\n\\r -~] trailing11)?
    trailing11 ::= ([\\t\\n\\r -~] trailing12)?
    trailing12 ::= ([\\t\\n\\r -~] trailing13)?
    trailing13 ::= ([\\t\\n\\r -~] trailing14)?
    trailing14 ::= ([\\t\\n\\r -~] trailing15)?
    trailing15 ::= ([\\t\\n\\r -~])?
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
