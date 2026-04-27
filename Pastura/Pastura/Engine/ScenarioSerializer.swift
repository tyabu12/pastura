import Foundation

/// Converts a ``Scenario`` model back to a YAML string.
///
/// The inverse of ``ScenarioLoader``: where the loader parses YAML → Scenario,
/// the serializer produces YAML from a Scenario. Uses the same field name
/// conventions as YAML presets (e.g., `agents` not `agentCount`, `output` not
/// `outputSchema`, phase-level `rounds` for `subRounds`, `exclude_self` for
/// `excludeSelf`).
///
/// Hand-builds YAML strings rather than using `Yams.dump()` to maintain
/// human-readable formatting consistent with preset YAML files.
nonisolated struct ScenarioSerializer: Sendable {

  /// Serialize a ``Scenario`` to a YAML string.
  ///
  /// The output is valid YAML that ``ScenarioLoader`` can round-trip.
  /// - Parameter scenario: The scenario to serialize.
  /// - Returns: A YAML string representation.
  func serialize(_ scenario: Scenario) -> String {
    var lines: [String] = []

    lines.append("id: \(scenario.id)")
    lines.append("name: \(yamlScalar(scenario.name))")
    lines.append("description: \(yamlScalar(scenario.description))")
    lines.append("agents: \(scenario.agentCount)")
    lines.append("rounds: \(scenario.rounds)")
    lines.append(yamlBlockScalar("context", scenario.context))

    // Extra data (top-level, before personas/phases)
    for key in scenario.extraData.keys.sorted() {
      if let value = scenario.extraData[key] {
        lines.append(serializeExtraData(key: key, value: value))
      }
    }

    // Personas
    lines.append("")
    lines.append("personas:")
    for persona in scenario.personas {
      lines.append("  - name: \(yamlScalar(persona.name))")
      lines.append("    description: \(yamlScalar(persona.description))")
    }

    // Phases
    lines.append("")
    lines.append("phases:")
    for phase in scenario.phases {
      lines.append(contentsOf: serializePhase(phase))
    }

    return lines.joined(separator: "\n") + "\n"
  }

  // MARK: - Phase Serialization

  // Each optional field adds one branch — unavoidable for 11 Phase fields.
  // swiftlint:disable:next cyclomatic_complexity
  private func serializePhase(_ phase: Phase) -> [String] {
    var lines: [String] = []

    lines.append("  - type: \(phase.type.rawValue)")

    if let prompt = phase.prompt {
      lines.append(yamlBlockScalar("prompt", prompt, indent: 4))
    }

    if let outputSchema = phase.outputSchema {
      lines.append("    output:")
      // Sort keys for deterministic output
      for (key, value) in outputSchema.sorted(by: { $0.key < $1.key }) {
        lines.append("      \(key): \(value)")
      }
    }

    if let options = phase.options {
      lines.append("    options:")
      for option in options {
        lines.append("      - \(option)")
      }
    }

    if let pairing = phase.pairing {
      lines.append("    pairing: \(pairing.rawValue)")
    }

    if let logic = phase.logic {
      lines.append("    logic: \(logic.rawValue)")
    }

    if let template = phase.template {
      lines.append(yamlBlockScalar("template", template, indent: 4))
    }

    if let source = phase.source {
      lines.append("    source: \(source)")
    }

    if let target = phase.target {
      lines.append("    target: \(target.rawValue)")
    }

    if let excludeSelf = phase.excludeSelf {
      lines.append("    exclude_self: \(excludeSelf)")
    }

    // Phase-level `rounds` key maps to `subRounds`
    if let subRounds = phase.subRounds {
      lines.append("    rounds: \(subRounds)")
    }

    // Conditional-specific fields — emitted at the end of the phase block
    // with 4-space indentation for nested sub-phase bodies.
    if let condition = phase.condition {
      lines.append("    if: \(yamlScalar(condition))")
    }
    // Empty arrays round-trip as `nil` (YAML has no disambiguator between
    // "key with empty list" and "key absent" under our manual-mapping parse
    // path). Skip emitting the key at all in that case so the output is
    // valid YAML and the loader's branch-shape check doesn't fire.
    if let thenPhases = phase.thenPhases, !thenPhases.isEmpty {
      lines.append("    then:")
      lines.append(contentsOf: serializeBranch(thenPhases, indent: 6))
    }
    if let elsePhases = phase.elsePhases, !elsePhases.isEmpty {
      lines.append("    else:")
      lines.append(contentsOf: serializeBranch(elsePhases, indent: 6))
    }

    // event_inject-specific fields. Probability is formatted with %g to
    // drop trailing zeros (1.0 → "1", 0.5 → "0.5") and suppress
    // floating-point precision dust (e.g., 0.1 + 0.2 → "0.3" not
    // "0.30000000000000004"). The loader's `parseOptionalDoubleAcceptingInt`
    // accepts both `1` (Int) and `1.0` (Double) so the round-trip is stable.
    if let probability = phase.probability {
      lines.append("    probability: \(formatProbability(probability))")
    }
    if let eventVariable = phase.eventVariable {
      lines.append("    as: \(yamlScalar(eventVariable))")
    }

    return lines
  }

  /// Formats a `Phase.probability` value for stable YAML round-trip.
  ///
  /// `%g` drops trailing zeros and uses the shortest accurate decimal,
  /// so ad-hoc constants stay human-readable while binary-precision
  /// dust is suppressed. Probability is bounded by the validator to
  /// `[0.0, 1.0]`, so the limited precision %g uses is always sufficient.
  private func formatProbability(_ value: Double) -> String {
    String(format: "%g", value)
  }

  /// Serializes an array of branch sub-phases at the given indent depth.
  ///
  /// Reuses `serializePhase` (which emits lines at "top-level" indentation:
  /// `  - type: ...` for the list marker and `    key: ...` for body lines,
  /// with block-scalar continuation lines at `      ...`). Nested branches
  /// need the same lines shifted uniformly by `indent - 2` spaces so that
  /// block-scalar continuation offsets are preserved.
  ///
  /// `serializePhase` returns an array of strings, but individual elements
  /// may themselves contain embedded `\n` (block scalars are pre-joined by
  /// `yamlBlockScalar`). We split on `\n` before padding so every emitted
  /// YAML line gets the shift — otherwise multi-line `prompt:` / `template:`
  /// values would lose their content-indent and produce unparseable YAML.
  private func serializeBranch(_ phases: [Phase], indent: Int) -> [String] {
    // `serializePhase` starts its first line at column 2 (`  - type: ...`).
    // The caller wants the list marker at `indent - 2` spaces (so body
    // lines land at `indent`, and block-scalar content lands at `indent + 2`).
    let shift = indent - 2
    guard shift > 0 else {
      // Branch indent ≤ top-level indent means no shift is needed; return
      // the inner lines verbatim.
      return phases.flatMap { serializePhase($0) }
    }
    let pad = String(repeating: " ", count: shift)
    var lines: [String] = []
    for phase in phases {
      for chunk in serializePhase(phase) {
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
          lines.append(pad + line)
        }
      }
    }
    return lines
  }

  // MARK: - Extra Data Serialization

  private func serializeExtraData(key: String, value: AnyCodableValue) -> String {
    switch value {
    case .string(let str):
      return "\(key): \(yamlScalar(str))"

    case .array(let items):
      var lines = ["\(key):"]
      for item in items {
        lines.append("  - \(yamlScalar(item))")
      }
      return lines.joined(separator: "\n")

    case .dictionary(let dict):
      var lines = ["\(key):"]
      for (fieldKey, fieldValue) in dict.sorted(by: { $0.key < $1.key }) {
        lines.append("  \(fieldKey): \(yamlScalar(fieldValue))")
      }
      return lines.joined(separator: "\n")

    case .arrayOfDictionaries(let arr):
      var lines = ["\(key):"]
      for dict in arr {
        var isFirst = true
        for (fieldKey, fieldValue) in dict.sorted(by: { $0.key < $1.key }) {
          if isFirst {
            lines.append("  - \(fieldKey): \(yamlScalar(fieldValue))")
            isFirst = false
          } else {
            lines.append("    \(fieldKey): \(yamlScalar(fieldValue))")
          }
        }
      }
      return lines.joined(separator: "\n")
    }
  }

  // MARK: - YAML Formatting Helpers

  /// Produces a YAML literal block scalar (using `|`) for multiline strings,
  /// or an inline scalar for single-line strings.
  ///
  /// Uses `|` (literal) rather than `>` (folded) so single newlines are
  /// preserved on round-trip — important for user-edited prompts and
  /// templates where line breaks may be semantically meaningful.
  private func yamlBlockScalar(_ key: String, _ value: String, indent: Int = 0) -> String {
    let prefix = String(repeating: " ", count: indent)

    if value.contains("\n") {
      // Literal block scalar (|) preserves all newlines verbatim
      var lines = ["\(prefix)\(key): |"]
      let contentIndent = prefix + "  "
      for line in value.split(separator: "\n", omittingEmptySubsequences: false) {
        lines.append("\(contentIndent)\(line)")
      }
      return lines.joined(separator: "\n")
    } else {
      return "\(prefix)\(key): \(yamlScalar(value))"
    }
  }

  /// Escapes a string for safe inline YAML if it contains special characters.
  /// Uses double-quoting when the value might be misinterpreted by a YAML parser.
  private func yamlScalar(_ value: String) -> String {
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
