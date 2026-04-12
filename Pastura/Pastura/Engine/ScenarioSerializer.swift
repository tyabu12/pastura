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

  private func serializePhase(_ phase: Phase) -> [String] {
    var lines: [String] = []

    lines.append("  - type: \(phase.type.rawValue)")

    if let prompt = phase.prompt {
      lines.append(yamlBlockScalar("prompt", prompt, indent: 4))
    }

    if let outputSchema = phase.outputSchema {
      lines.append("    output:")
      // Sort keys for deterministic output
      for key in outputSchema.keys.sorted() {
        lines.append("      \(key): \(outputSchema[key]!)")
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
      lines.append("    target: \(target)")
    }

    if let excludeSelf = phase.excludeSelf {
      lines.append("    exclude_self: \(excludeSelf)")
    }

    // Phase-level `rounds` key maps to `subRounds`
    if let subRounds = phase.subRounds {
      lines.append("    rounds: \(subRounds)")
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
      for k in dict.keys.sorted() {
        lines.append("  \(k): \(yamlScalar(dict[k]!))")
      }
      return lines.joined(separator: "\n")

    case .arrayOfDictionaries(let arr):
      var lines = ["\(key):"]
      for dict in arr {
        var isFirst = true
        for k in dict.keys.sorted() {
          if isFirst {
            lines.append("  - \(k): \(yamlScalar(dict[k]!))")
            isFirst = false
          } else {
            lines.append("    \(k): \(yamlScalar(dict[k]!))")
          }
        }
      }
      return lines.joined(separator: "\n")
    }
  }

  // MARK: - YAML Formatting Helpers

  /// Produces a YAML block scalar (using `>`) for multiline strings,
  /// or an inline scalar for single-line strings.
  private func yamlBlockScalar(_ key: String, _ value: String, indent: Int = 0) -> String {
    let prefix = String(repeating: " ", count: indent)

    if value.contains("\n") {
      // Use folded block scalar (>) for multiline
      var lines = ["\(prefix)\(key): >"]
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
