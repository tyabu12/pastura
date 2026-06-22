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
  /// look-alikes, line breaks). Otherwise returns the value verbatim.
  static func quote(_ value: String) -> String {
    // Values that need quoting: empty, contains special chars, looks like number/bool
    let needsQuoting =
      value.isEmpty
      || value.hasPrefix("{") || value.hasPrefix("[")
      || value.hasPrefix("*") || value.hasPrefix("&")
      || value.hasPrefix("!") || value.hasPrefix("%")
      || value.hasPrefix("'") || value.hasPrefix("\"")
      || value.contains(": ") || value.contains(" #")
      || value.hasPrefix("- ") || value.hasPrefix("? ")
      || value == "true" || value == "false"
      || value == "null" || value == "~"
      || value.contains("\n") || value.contains("\r")
      || Int(value) != nil || Double(value) != nil

    if needsQuoting {
      let escaped =
        value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      return "\"\(escaped)\""
    }

    return value
  }
}
