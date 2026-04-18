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

    return lines
  }

  /// Serializes an array of branch sub-phases at the given indent depth.
  ///
  /// Reuses `serializePhase` but replaces the top-level two-space `  -`
  /// prefix with a deeper indent so nested phases align under their
  /// `then:` / `else:` key.
  private func serializeBranch(_ phases: [Phase], indent: Int) -> [String] {
    var lines: [String] = []
    let prefix = String(repeating: " ", count: indent)
    for phase in phases {
      let inner = serializePhase(phase)
      // `serializePhase` emits `  - type: ...` then `    key: ...` lines.
      // Re-indent those to sit under the parent's then/else block.
      for (offset, line) in inner.enumerated() {
        if offset == 0 {
          // First line starts with "  - "; re-emit at the new indent.
          let stripped = line.drop(while: { $0 == " " })
          lines.append("\(prefix.dropLast(2))\(stripped)")
        } else {
          let stripped = line.drop(while: { $0 == " " })
          lines.append("\(prefix)\(stripped)")
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
