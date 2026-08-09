import Foundation

/// Translates an ``OutputSchema`` into a GBNF grammar string suitable for
/// llama.cpp's `llama_sampler_init_grammar`.
///
/// The grammar shape is fixed: a JSON object root with fields in the
/// schema's declared order (primary-first per ``OutputSchema``), plus
/// shared `string` + `ws` productions. String content accepts any UTF-8
/// byte sequence via `[^"\\]` — Japanese / emoji pass through without a
/// separate code-point class.
///
/// Every field's value position uses the shared `string` production —
/// the grammar constrains JSON **structure** (object shape, keys, commas)
/// but never enumerates values. Author-defined choice options
/// (`choose.action`) were once emitted as alternation literals, but that
/// crashed llama.cpp's sampler on CJK / dynamic values; value constraint
/// now lives at runtime (``ChooseHandler`` `validateAction`). See
/// ``OutputSchema/Kind/choice`` and ADR-002 §12.8 for the history.
///
/// Pure transformation — no I/O, no state. Output is stable and testable
/// byte-for-byte against golden files for each preset (see
/// `GBNFGrammarBuilderTests`).
nonisolated public struct GBNFGrammarBuilder: Sendable {
  public init() {}

  /// Errors this builder throws. All indicate caller-side validation
  /// failures that should never reach runtime under normal use — caller
  /// bugs, not user bugs. In production these should be caught by the
  /// golden-file tests; at runtime they surface as
  /// ``LLMError/invalidGrammar`` (Item 4) so the retry budget is
  /// preserved.
  nonisolated public enum BuilderError: Error, Equatable, Sendable {
    /// Two ``OutputSchema/Field`` entries share the same name.
    case duplicateFieldName(String)
    /// Field name is not a valid ASCII identifier per
    /// ``ScenarioConventions/isValidFieldName(_:)``: first char must be an
    /// ASCII letter (`[A-Za-z]`) and subsequent chars ASCII letter / digit /
    /// `_`. Field names are emitted as JSON-key literals (`"\"name\""`) in
    /// the grammar; a non-ASCII / multi-byte key reaches llama.cpp's sampler
    /// as a literal and crashes it at accept-time on-device (the "empty
    /// grammar stack" SIGABRT class — same mechanism as the #599 CJK
    /// choose-option removal; #607). Leading `_` / `-` stay rejected as a
    /// conservative hygiene rule. This builder check is the unconditional
    /// crash backstop; ``ScenarioValidator`` surfaces the same rule earlier
    /// as a clear load-time error.
    case invalidFieldName(String)
  }

  /// Build the complete grammar for ``OutputSchema``.
  ///
  /// - Returns: a multi-line GBNF string beginning with `root ::= …` and
  ///   ending with the shared `ws ::= [ \t\n]*` production.
  public func build(from schema: OutputSchema) throws -> String {
    try validate(schema: schema)

    var rules: [String] = []
    rules.append(rootRule(for: schema))
    rules.append(Self.sharedStringProduction)
    rules.append(Self.sharedWhitespaceProduction)
    rules.append(Self.sharedTrailingProduction)
    return rules.joined(separator: "\n")
  }

  // MARK: - Rule builders

  private func rootRule(for schema: OutputSchema) -> String {
    // GBNF literal helpers: every `"X"` in the output is a 3-char sequence
    // `"`, X, `"`. Quoted-name literals like `"\"statement\""` are 4 + name
    // chars. Using escape-based regular strings (not raw) because the
    // nested `"` / `\"` combinations are hard to read in `#"..."#` form.
    let openBrace = "\"{\""
    let closeBrace = "\"}\""
    let comma = "\",\""
    let colon = "\":\""
    var parts: [String] = [openBrace, "ws"]
    for (index, field) in schema.fields.enumerated() {
      if index > 0 {
        parts.append(comma)
        parts.append("ws")
      }
      parts.append("\"\\\"\(field.name)\\\"\"")
      parts.append("ws")
      parts.append(colon)
      parts.append("ws")
      parts.append(valueRuleName(for: field))
      parts.append("ws")
    }
    parts.append(closeBrace)
    // Trailing rule reference (see `sharedTrailingProduction`) is
    // load-bearing: without trailing coverage, `accept_token` throws
    // `std::runtime_error("Unexpected empty grammar stack after
    // accepting piece: …")` when Gemma samples a BPE-merged token
    // like `}: ` (token 7493) — `}` closes the object but the
    // trailing bytes in the same token have no grammar home.
    //
    // The `trailing` rule is a BOUNDED chain (depth
    // `trailingByteBudget`) of `(byte trailingN)?` productions rather
    // than an unbounded self-reference. Recursive `(byte trailingN)?`
    // form (not inline `[^"\\]*`) because llama.cpp's grammar parser
    // intermittently rejects Kleene-star on top-level char classes
    // (same symptom that made us switch `ws` to its recursive form
    // earlier in this PR). The previous UNBOUNDED form absorbed
    // unlimited printable ASCII after the close — inviting the model to
    // emit fabricated follow-on objects that then tripped the parser's
    // multi-object refusal (#907). The bound caps residue at
    // `trailingByteBudget` bytes; overflow lands on the catch-as-EOS
    // path (the prior commit) — a benign stop after the object is
    // already complete, not the old hard failure.
    parts.append("trailing")
    return "root ::= \(parts.joined(separator: " "))"
  }

  private func valueRuleName(for field: OutputSchema.Field) -> String {
    // Both kinds use the shared `string` production — the grammar
    // constrains structure, not values (see type doc and
    // ``OutputSchema/Kind/choice``).
    switch field.kind {
    case .string, .choice:
      return "string"
    }
  }

  // MARK: - Validation

  private func validate(schema: OutputSchema) throws {
    var seen: Set<String> = []
    for field in schema.fields {
      try validateFieldName(field.name)
      if seen.contains(field.name) {
        throw BuilderError.duplicateFieldName(field.name)
      }
      seen.insert(field.name)
    }
  }

  private func validateFieldName(_ name: String) throws {
    // Field names are emitted as JSON-key literals (`"\"name\""`) in the
    // grammar. A non-ASCII / multi-byte key reaches llama.cpp's sampler as a
    // literal and crashes it at accept-time on-device (the "empty grammar
    // stack" SIGABRT class — same mechanism as the #599 CJK choose-option
    // removal; #607). The ASCII-identifier rule lives on
    // `ScenarioConventions.isValidFieldName` as the single source of truth
    // shared with `ScenarioValidator`; this builder check is the
    // unconditional crash backstop for paths that bypass the validator
    // (demo replays, direct LLMCaller tests, a future harness).
    guard ScenarioConventions.isValidFieldName(name) else {
      throw BuilderError.invalidFieldName(name)
    }
  }

  // MARK: - Shared productions

  /// JSON string production — accepts any UTF-8 byte via `[^"\\]` plus
  /// the six JSON escape forms and `\uXXXX`. Matches the standard
  /// grammar from llama.cpp's `grammars/README.md`.
  private static let sharedStringProduction =
    #"string ::= "\"" ( [^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) )* "\"""#

  // Recursive form matches llama.cpp's official `grammars/json.gbnf`
  // verbatim. The Kleene-star form `ws ::= [ \t\n]*` is valid per the
  // GBNF spec but reportedly triggered intermittent
  // `llama_sampler_init_grammar` NULL returns in TestFlight (#194 PR#b);
  // switching to the upstream-proven recursive form is a conservative
  // hedge.
  private static let sharedWhitespaceProduction = #"ws ::= ([ \t\n] ws)?"#

  /// Max bytes the bounded `trailing` chain absorbs after the closing `}`.
  /// Covers any single BPE-merged close token's residue (`}: `, token 7493)
  /// with margin; overflow past this budget lands on the catch-as-EOS path
  /// (#907) — a benign stop once the object is already complete.
  private static let trailingByteBudget = 16

  // Trailing rule used after the closing `}` to tolerate BPE-merged
  // tokens whose tail continues past the object boundary. BOUNDED
  // recursive chain (`trailingByteBudget` links) + positive char class.
  //
  // History (all returned NULL from `llama_sampler_init_grammar` unless
  // noted):
  //   1. `ws` reuse (`"}" ws` at top level)           — OK parse, crash on `}: ` accept
  //   2. inline `[^\x00]*`                             — parse NULL
  //   3. inline `[^"\\]*`                              — parse NULL
  //   4. recursive `trailing ::= ([^"\\] trailing)?`   — parse NULL
  //   5. recursive + positive class (unbounded)        — parsed OK, but the
  //      unlimited printable-ASCII acceptance let the model emit fabricated
  //      follow-on objects that tripped the multi-object refusal (#907)
  //   6. bounded chain + positive class (this commit)  — caps residue
  //
  // Hypothesis: llama.cpp's grammar parser has an edge case with
  // negated char classes when used in a recursive rule (theory 4),
  // even though `[^"\\]` works inside `string`'s grouped alternation.
  // Positive class `[\t\n\r -~]` avoids negation entirely.
  //
  // Coverage: tab, CR, LF, space through tilde (0x20-0x7e) —
  // all printable ASCII plus whitespace. Post-`}` tokens from Gemma
  // are almost always whitespace, chat-template fragments (Gemma 4's
  // markers are `<|turn>` / `<turn|>`) or EOS; all fit in this range.
  // Non-ASCII post-`}` bytes would still cause an accept-time crash,
  // but the model is trained to emit EOS immediately after a closed
  // object so that path is practically unreachable.
  //
  // Emits, e.g. for budget 16:
  //   trailing   ::= ([\t\n\r -~] trailing1)?
  //   trailing1  ::= ([\t\n\r -~] trailing2)?
  //   …
  //   trailing15 ::= ([\t\n\r -~])?
  // The terminal link omits the self-reference, capping the chain.
  private static var sharedTrailingProduction: String {
    (0..<trailingByteBudget).map { depth in
      let ruleName = depth == 0 ? "trailing" : "trailing\(depth)"
      if depth == trailingByteBudget - 1 {
        // Terminal link — no next-reference, bounds the chain length.
        return #"\#(ruleName) ::= ([\t\n\r -~])?"#
      }
      return #"\#(ruleName) ::= ([\t\n\r -~] trailing\#(depth + 1))?"#
    }
    .joined(separator: "\n")
  }
}
