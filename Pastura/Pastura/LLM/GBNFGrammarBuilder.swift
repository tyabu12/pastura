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
/// Enumeration fields (currently only `choose.action` with non-empty
/// options) get a per-field rule named `<fieldname>_value` with the
/// options as alternation literals. This is strictly stronger than the
/// runtime `validateAction` fallback: the model cannot produce an
/// out-of-set value in the first place.
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
    /// `.enumeration([])` — a choose-phase options list was empty or
    /// missing; grammar would have zero alternatives, which llama.cpp
    /// rejects.
    case emptyEnumeration(field: String)
    /// Two ``OutputSchema/Field`` entries share the same name.
    case duplicateFieldName(String)
    /// Field name does not match the GBNF rule-name shape
    /// `[a-zA-Z_][a-zA-Z0-9_]*`. Pastura's presets are snake_case,
    /// which passes.
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
    for field in schema.fields {
      if case .enumeration(let options) = field.kind {
        rules.append(enumerationRule(name: field.name, options: options))
      }
    }
    rules.append(Self.sharedStringProduction)
    rules.append(Self.sharedWhitespaceProduction)
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
    return "root ::= \(parts.joined(separator: " "))"
  }

  private func valueRuleName(for field: OutputSchema.Field) -> String {
    switch field.kind {
    case .string:
      return "string"
    case .enumeration:
      return "\(field.name)_value"
    }
  }

  private func enumerationRule(name: String, options: [String]) -> String {
    let alternatives =
      options
      .map { #""\""# + $0 + #"\"""# }
      .joined(separator: " | ")
    return "\(name)_value ::= \(alternatives)"
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
      if case .enumeration(let options) = field.kind, options.isEmpty {
        throw BuilderError.emptyEnumeration(field: field.name)
      }
    }
  }

  private func validateFieldName(_ name: String) throws {
    guard let first = name.first, first.isLetter || first == "_" else {
      throw BuilderError.invalidFieldName(name)
    }
    for char in name where !(char.isLetter || char.isNumber || char == "_") {
      throw BuilderError.invalidFieldName(name)
    }
  }

  // MARK: - Shared productions

  /// JSON string production — accepts any UTF-8 byte via `[^"\\]` plus
  /// the six JSON escape forms and `\uXXXX`. Matches the standard
  /// grammar from llama.cpp's `grammars/README.md`.
  private static let sharedStringProduction =
    #"string ::= "\"" ( [^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) )* "\"""#

  private static let sharedWhitespaceProduction = #"ws ::= [ \t\n]*"#
}
