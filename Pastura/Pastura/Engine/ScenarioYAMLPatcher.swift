import Foundation
import Yams

/// Format-preserving visual→YAML boundary sync (ADR-018).
///
/// Produces YAML for a `visual` ``Scenario`` while preserving the comments,
/// key order, and quoting of a `base` YAML string for every value the user did
/// not change. When only **inline scalar values** changed (no structural
/// change), the original `base` text is emitted with just those value spans
/// spliced in place. Anything else — structural changes (persona/phase
/// add/remove/reorder, phase `type` change, list-length change), block-scalar
/// edits (`context`/`prompt`/`template`), a blank or unparseable base, or any
/// uncertainty in locating a value span — falls back to canonical
/// ``ScenarioSerializer`` output.
///
/// The patcher is an **optimization over** `ScenarioSerializer.serialize`: it
/// is correct-by-fallback. A reparse safety-net (`load(patched) == visual`)
/// guards against any splice bug, so the patcher can never emit YAML that
/// disagrees with `visual` — at worst it degrades to today's full serialize.
/// It is a **pure function** of `(visual, base)` and reads no editor state.
nonisolated public struct ScenarioYAMLPatcher: Sendable {

  private let loader = ScenarioLoader()
  private let serializer = ScenarioSerializer()

  public init() {}

  /// A single inline-scalar value replacement located in the base text.
  private struct ScalarEdit {
    let mark: Mark
    let style: Node.Scalar.Style
    let rendered: String
  }

  /// Returns YAML for `visual`, preserving `base` formatting where unchanged.
  public func patch(visual: Scenario, base: String) -> String {
    let fallback = serializer.serialize(visual)

    guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let baseScenario = try? loader.load(yaml: base),
      let root = try? Yams.compose(yaml: base)
    else { return fallback }

    guard !hasStructuralChange(base: baseScenario, visual: visual),
      let edits = collectEdits(base: baseScenario, visual: visual, root: root),
      let patched = applyEdits(edits, to: base)
    else { return fallback }

    // Reparse safety-net: any divergence — including a parse failure (load
    // throws on construct-time invariants, see .claude/rules/engine.md
    // § "Parse vs validate boundary") — falls back.
    do {
      let reparsed = try loader.load(yaml: patched)
      guard reparsed == visual else { return fallback }
    } catch {
      return fallback
    }
    return patched
  }

  // MARK: - Structural change detection

  /// `true` when `visual` differs from `base` in a way a value-splice cannot
  /// represent (counts, types, or list/nested-collection contents).
  private func hasStructuralChange(base: Scenario, visual: Scenario) -> Bool {
    if base.personas.count != visual.personas.count { return true }
    if base.phases.count != visual.phases.count { return true }
    if base.extraData != visual.extraData { return true }
    for (basePhase, visualPhase) in zip(base.phases, visual.phases) {
      if basePhase.type != visualPhase.type { return true }
      if basePhase.options != visualPhase.options { return true }
      if basePhase.outputSchema != visualPhase.outputSchema { return true }
      if basePhase.thenPhases != visualPhase.thenPhases { return true }
      if basePhase.elsePhases != visualPhase.elsePhases { return true }
    }
    return false
  }

  // MARK: - Edit collection

  /// Collects an edit for every changed inline scalar. Returns `nil` to signal
  /// a forced fallback (a changed value whose key is absent, is a block scalar,
  /// or otherwise cannot be rendered inline).
  private func collectEdits(base: Scenario, visual: Scenario, root: Node) -> [ScalarEdit]? {
    var edits: [ScalarEdit] = []
    guard topLevelEdits(base, visual, root, into: &edits),
      personaEdits(base, visual, root, into: &edits),
      phaseEdits(base, visual, root, into: &edits)
    else { return nil }
    return edits
  }

  private func topLevelEdits(
    _ base: Scenario, _ visual: Scenario, _ root: Node, into edits: inout [ScalarEdit]
  ) -> Bool {
    let quote = YAMLScalarFormatter.quote
    return tryEdit(base.id != visual.id, root["id"]?.scalar, visual.id, &edits)
      && tryEdit(base.name != visual.name, root["name"]?.scalar, quote(visual.name), &edits)
      && tryEdit(
        base.description != visual.description, root["description"]?.scalar,
        quote(visual.description), &edits)
      && tryEdit(
        base.language != visual.language, root["language"]?.scalar, visual.language, &edits)
      && tryEdit(
        base.simulationLanguage != visual.simulationLanguage,
        root["simulation_language"]?.scalar, visual.simulationLanguage, &edits)
      && tryEdit(
        base.rounds != visual.rounds, root["rounds"]?.scalar, String(visual.rounds), &edits)
      && tryEdit(
        base.context != visual.context, root["context"]?.scalar, quote(visual.context), &edits)
  }

  private func personaEdits(
    _ base: Scenario, _ visual: Scenario, _ root: Node, into edits: inout [ScalarEdit]
  ) -> Bool {
    let quote = YAMLScalarFormatter.quote
    for index in visual.personas.indices {
      let basePersona = base.personas[index]
      let visualPersona = visual.personas[index]
      guard
        tryEdit(
          basePersona.name != visualPersona.name, nestedScalar(root, "personas", index, "name"),
          quote(visualPersona.name), &edits),
        tryEdit(
          basePersona.description != visualPersona.description,
          nestedScalar(root, "personas", index, "description"), quote(visualPersona.description),
          &edits)
      else { return false }
    }
    return true
  }

  private func phaseEdits(
    _ base: Scenario, _ visual: Scenario, _ root: Node, into edits: inout [ScalarEdit]
  ) -> Bool {
    for index in visual.phases.indices
    where !phaseScalarEdits(base.phases[index], visual.phases[index], root, index, &edits) {
      return false
    }
    return true
  }

  private func phaseScalarEdits(
    _ base: Phase, _ visual: Phase, _ root: Node, _ index: Int, _ edits: inout [ScalarEdit]
  ) -> Bool {
    let quote = YAMLScalarFormatter.quote
    func node(_ field: String) -> Node.Scalar? { nestedScalar(root, "phases", index, field) }
    return tryEdit(
      base.prompt != visual.prompt, node("prompt"), visual.prompt.map(quote), &edits)
      && tryEdit(
        base.template != visual.template, node("template"), visual.template.map(quote), &edits)
      && tryEdit(base.source != visual.source, node("source"), visual.source, &edits)
      && tryEdit(base.target != visual.target, node("target"), visual.target?.rawValue, &edits)
      && tryEdit(base.pairing != visual.pairing, node("pairing"), visual.pairing?.rawValue, &edits)
      && tryEdit(base.logic != visual.logic, node("logic"), visual.logic?.rawValue, &edits)
      && tryEdit(
        base.condition != visual.condition, node("if"), visual.condition.map(quote), &edits)
      && tryEdit(
        base.probability != visual.probability, node("probability"),
        visual.probability.map(Self.formatProbability), &edits)
      && tryEdit(
        base.eventVariable != visual.eventVariable, node("as"), visual.eventVariable.map(quote),
        &edits)
      && tryEdit(
        base.excludeSelf != visual.excludeSelf, node("exclude_self"),
        visual.excludeSelf.map(String.init), &edits)
      && tryEdit(
        base.subRounds != visual.subRounds, node("rounds"), visual.subRounds.map(String.init),
        &edits)
  }

  /// Appends an edit when `changed`. Returns `false` (forcing a fallback) when a
  /// changed value cannot be patched in place: key absent (`node == nil`), block
  /// scalar (D4), or `nil` render (an optional field was removed — structural).
  private func tryEdit(
    _ changed: Bool, _ node: Node.Scalar?, _ rendered: String?, _ edits: inout [ScalarEdit]
  ) -> Bool {
    guard changed else { return true }
    guard let scalar = node, let mark = scalar.mark else { return false }
    guard scalar.style != .literal, scalar.style != .folded else { return false }
    guard let rendered else { return false }
    edits.append(ScalarEdit(mark: mark, style: scalar.style, rendered: rendered))
    return true
  }

  /// Matches `ScenarioSerializer.formatProbability` (`%g`) so probability splices
  /// stay byte-identical to the full-serialize fallback.
  private static func formatProbability(_ value: Double) -> String {
    String(format: "%g", value)
  }

  private func nestedScalar(
    _ root: Node, _ listKey: String, _ index: Int, _ field: String
  ) -> Node.Scalar? {
    guard let sequence = root[listKey]?.sequence, index >= 0, index < sequence.count else {
      return nil
    }
    return sequence[index][field]?.scalar
  }

  // MARK: - Text splicing

  /// Applies edits to the base text line-by-line. Returns `nil` (forcing a
  /// fallback) when two edits target the same line (flow-style risk) or a line
  /// cannot be spliced.
  private func applyEdits(_ edits: [ScalarEdit], to base: String) -> String? {
    guard !edits.isEmpty else { return base }
    var byLine: [Int: ScalarEdit] = [:]
    for edit in edits {
      if byLine[edit.mark.line] != nil { return nil }
      byLine[edit.mark.line] = edit
    }
    var lines = base.components(separatedBy: "\n")
    for (lineNumber, edit) in byLine {
      let lineIndex = lineNumber - 1
      guard lines.indices.contains(lineIndex),
        let spliced = spliceLine(
          lines[lineIndex], column: edit.mark.column, style: edit.style,
          rendered: edit.rendered)
      else { return nil }
      lines[lineIndex] = spliced
    }
    return lines.joined(separator: "\n")
  }

  /// Replaces the value span starting at `column` (1-based, Unicode scalars)
  /// with `rendered`, preserving the prefix (`key: `) and any trailing comment.
  private func spliceLine(
    _ line: String, column: Int, style: Node.Scalar.Style, rendered: String
  ) -> String? {
    let scalars = Array(line.unicodeScalars)
    let start = column - 1
    guard start >= 0, start <= scalars.count else { return nil }
    let remainder = Array(scalars[start...])
    guard let valueEnd = valueEndOffset(remainder, style: style) else { return nil }
    let prefix = String(String.UnicodeScalarView(scalars[0..<start]))
    let tail = String(String.UnicodeScalarView(remainder[valueEnd...]))
    return prefix + rendered + tail
  }

  /// Offset (into `scalars`) where the old value ends and the tail (trailing
  /// comment / whitespace) begins.
  private func valueEndOffset(_ scalars: [Unicode.Scalar], style: Node.Scalar.Style) -> Int? {
    switch style {
    case .singleQuoted: return closingQuote(scalars, quote: "'", escapedByDoubling: true)
    case .doubleQuoted: return closingQuote(scalars, quote: "\"", escapedByDoubling: false)
    case .plain, .any: return plainValueEnd(scalars)
    case .literal, .folded: return nil  // block — guarded upstream
    }
  }

  /// Plain scalar: the value ends after its last non-whitespace scalar; all
  /// trailing whitespace and any ` #` comment become the preserved tail. A `#`
  /// counts as a comment only when preceded by whitespace (or at line start) —
  /// an interior `#` (`ff#00`) stays part of the value.
  private func plainValueEnd(_ scalars: [Unicode.Scalar]) -> Int {
    var commentStart = scalars.count
    var index = 0
    while index < scalars.count {
      if scalars[index] == "#", index == 0 || isInlineWhitespace(scalars[index - 1]) {
        commentStart = index
        break
      }
      index += 1
    }
    var end = commentStart
    while end > 0, isTrailingWhitespace(scalars[end - 1]) { end -= 1 }
    return end
  }

  /// Quoted scalar: tail starts immediately after the closing quote. Returns
  /// `nil` for an unterminated quote (forces a fallback).
  private func closingQuote(
    _ scalars: [Unicode.Scalar], quote: Unicode.Scalar, escapedByDoubling: Bool
  ) -> Int? {
    guard scalars.first == quote else { return nil }
    var index = 1
    while index < scalars.count {
      if !escapedByDoubling, scalars[index] == "\\" {
        index += 2  // skip the escaped scalar (double-quoted YAML)
        continue
      }
      if scalars[index] == quote {
        if escapedByDoubling, index + 1 < scalars.count, scalars[index + 1] == quote {
          index += 2  // `''` — an escaped single quote
          continue
        }
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private func isTrailingWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n"
  }

  private func isInlineWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t"
  }
}
