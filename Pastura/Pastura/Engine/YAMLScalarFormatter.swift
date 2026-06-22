import Foundation

/// Shared YAML inline-scalar quoting rules.
///
/// Extracted from ``ScenarioSerializer`` so the full-serialize path and the
/// format-preserving ``ScenarioYAMLPatcher`` (ADR-018) quote new scalar values
/// by **identical** rules. Keeping the two in lockstep is load-bearing: if the
/// patcher spliced a value that the serializer would have quoted (or vice
/// versa), the patched and fallback outputs could disagree — a silent
/// corruption source. Both consume this single helper so a future quoting-rule
/// change cannot desync them.
nonisolated enum YAMLScalarFormatter {

  /// Escapes a string for safe inline YAML if it contains special characters.
  ///
  /// Uses double-quoting when the value might be misinterpreted by a YAML
  /// parser (empty, leading indicators, embedded `: ` / ` #`, number/bool
  /// look-alikes, line breaks, surrounding whitespace). Otherwise returns the
  /// value verbatim. Inside the double-quoted form, line breaks and tabs are
  /// emitted as `\n` / `\r` / `\t` escapes — a *literal* LF/CR in a
  /// double-quoted scalar is folded/normalized to a space on reparse, so an
  /// unescaped break silently corrupts the round-trip (#749).
  static func quote(_ value: String) -> String {
    // `.whitespaces` is space + tab; a value differing from its trimmed form
    // has leading/trailing/all whitespace, which a *plain* scalar strips on
    // reparse — so it must be quoted. (Leading/trailing line breaks are caught
    // separately by the `\n` / `\r` checks below.)
    let trimmed = value.trimmingCharacters(in: .whitespaces)

    // Values that need quoting: empty, contains special chars, looks like number/bool
    let needsQuoting =
      value.isEmpty
      || value.hasPrefix("{") || value.hasPrefix("[")
      || value.hasPrefix("*") || value.hasPrefix("&")
      || value.hasPrefix("!") || value.hasPrefix("%")
      || value.hasPrefix("'") || value.hasPrefix("\"")
      // YAML indicator characters that cannot safely begin a plain scalar.
      // `@`/`` ` `` are spec-reserved (§5.3); `|`/`>` are block-scalar headers
      // and `,`/`=` are flow/reserved indicators. libyaml's tolerance for
      // these in block-mapping value position is inconsistent and
      // version-dependent (e.g. `>x` errors while `|x` parses), so quote them
      // all defensively rather than rely on a parser quirk.
      || value.hasPrefix("@") || value.hasPrefix("`")
      || value.hasPrefix("|") || value.hasPrefix(">")
      || value.hasPrefix(",") || value.hasPrefix("=")
      || value.contains(": ") || value.contains(" #")
      || value.hasPrefix("- ") || value.hasPrefix("? ")
      // A bare `:` parses as a mapping indicator ("mapping values are not
      // allowed in this context") rather than the scalar `:`.
      || value == ":"
      || value == "true" || value == "false"
      || value == "null" || value == "~"
      // Scalar-level check: `contains("\n")` is grapheme-aware and misses the
      // LF inside a CRLF cluster (Swift fuses `\r\n` into one Character), so a
      // CRLF value would slip through unquoted. Inspect unicode scalars.
      || value.unicodeScalars.contains("\n") || value.unicodeScalars.contains("\r")
      || value != trimmed
      || Int(value) != nil || Double(value) != nil

    if needsQuoting {
      // Order matters: backslash first (so escapes we add below are not
      // re-escaped), then the quote delimiter, then the break/tab escapes.
      // `.literal` matches by unicode scalar, not grapheme cluster — required
      // so the LF and CR inside a CRLF cluster are each escaped (default,
      // grapheme-aware matching would skip them and leak a literal break).
      let escaped =
        value
        .replacingOccurrences(of: "\\", with: "\\\\", options: .literal)
        .replacingOccurrences(of: "\"", with: "\\\"", options: .literal)
        .replacingOccurrences(of: "\n", with: "\\n", options: .literal)
        .replacingOccurrences(of: "\r", with: "\\r", options: .literal)
        .replacingOccurrences(of: "\t", with: "\\t", options: .literal)
      return "\"\(escaped)\""
    }

    return value
  }
}
