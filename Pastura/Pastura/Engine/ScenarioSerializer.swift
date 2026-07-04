import Foundation
import Yams

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
    lines.append("language: \(scenario.language)")
    if let simulationLanguage = scenario.simulationLanguage {
      lines.append("simulation_language: \(simulationLanguage)")
    }
    lines.append("name: \(yamlScalar(scenario.name))")
    // `description` may be a multi-paragraph brief; route it through
    // `yamlReadableBlockScalar` so a multi-line value renders as a readable
    // `|-` literal block instead of an escaped one-liner (#752). Single-line
    // descriptions still serialize inline via the helper's fallback branch.
    lines.append(yamlReadableBlockScalar("description", scenario.description))
    lines.append("agents: \(scenario.agentCount)")
    lines.append("rounds: \(scenario.rounds)")
    // Optional prompt-side conversation-log cap (#907); omit the key when nil
    // so scenarios without a window round-trip unchanged.
    if let logWindow = scenario.logWindow {
      lines.append("log_window: \(logWindow)")
    }
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
      // `indent: 4` nests the block scalar under the `  - name:` list item
      // (marker at column 4, content at column 6); with the default `indent: 0`
      // a multi-line persona description would break the persona mapping (#752).
      lines.append(yamlReadableBlockScalar("description", persona.description, indent: 4))
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

  // Each optional field adds one branch — unavoidable for 13 Phase fields
  // (added probability + as for event_inject in #256). The body length
  // grows linearly with field count too.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
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
      // Stays on the inline (`yamlScalar`) path — a multi-line extraData string
      // renders as an escaped one-liner, which round-trips correctly (#749) but
      // is less readable than a `|` block. Block-scalar output for extraData is
      // deferred (#752): the array/dict/arrayOfDictionaries branches below would
      // each need block-scalar indentation threaded through their nesting.
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

  /// Produces a **strip-chomped** YAML literal block scalar (`|-`) for a
  /// multi-line value that round-trips verbatim, or an inline scalar otherwise.
  ///
  /// Used for user-authored prose fields (`description`, persona `description`)
  /// where a multi-paragraph value should read as a `|-` block rather than an
  /// escaped one-liner (#752). Differs from ``yamlBlockScalar`` in chomping:
  /// the clip `|` form appends a trailing newline on reload, which breaks an
  /// **exact** round-trip for the common no-trailing-newline shape; strip `|-`
  /// round-trips it verbatim.
  ///
  /// The block form is emitted only when a **self-verifying reparse** confirms
  /// it parses back to the exact value: several multi-line shapes don't survive
  /// a literal block (a value ending in a newline loses it to strip chomping; a
  /// first line with leading whitespace makes the block unparseable; `CRLF` and
  /// some whitespace-only lines normalize). Any such value — and every
  /// single-line value — falls back to the inline (escaped) path, which
  /// ``YAMLScalarFormatter`` guarantees round-trips for any string (#749). The
  /// reparse uses the same ``Yams`` parser ``ScenarioLoader`` loads with, so the
  /// gate can never disagree with the loader, mirroring the
  /// ``ScenarioYAMLPatcher`` reparse safety-net (ADR-018).
  private func yamlReadableBlockScalar(_ key: String, _ value: String, indent: Int = 0) -> String {
    func block(_ pfx: String) -> String {
      var lines = ["\(pfx)\(key): |-"]
      let contentIndent = pfx + "  "
      for line in value.split(separator: "\n", omittingEmptySubsequences: false) {
        lines.append("\(contentIndent)\(line)")
      }
      return lines.joined(separator: "\n")
    }

    let prefix = String(repeating: " ", count: indent)
    let inline = "\(prefix)\(key): \(yamlScalar(value))"

    // Self-verify the relative structure at indent 0 — the block's
    // parse-ability and round-trip fidelity depend only on the content lines'
    // indentation relative to the marker, which `indent` shifts uniformly.
    guard value.contains("\n"),
      let parsed = try? Yams.load(yaml: block("")) as? [String: Any],
      parsed[key] as? String == value
    else { return inline }
    return block(prefix)
  }

  /// Escapes a string for safe inline YAML if it contains special characters.
  /// Uses double-quoting when the value might be misinterpreted by a YAML parser.
  ///
  /// Delegates to the shared ``YAMLScalarFormatter`` so the format-preserving
  /// ``ScenarioYAMLPatcher`` (ADR-018) quotes spliced values by identical rules.
  private func yamlScalar(_ value: String) -> String {
    YAMLScalarFormatter.quote(value)
  }
}
