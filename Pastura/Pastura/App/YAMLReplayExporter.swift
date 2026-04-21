// swiftlint:disable file_length
import Foundation

/// Errors produced by ``YAMLReplayExporter``.
nonisolated enum YAMLReplayExporterError: Error, LocalizedError, Equatable {
  /// The scenario's stored YAML could not be parsed as a ``Scenario``.
  /// Without a parsed scenario the exporter cannot compute `phase_index`
  /// or validate persona names — export is refused rather than emit a
  /// broken replay document.
  case scenarioYAMLInvalid
  /// Writing the exported YAML to a temporary file failed.
  case ioFailed(description: String)

  var errorDescription: String? {
    switch self {
    case .scenarioYAMLInvalid:
      return String(
        localized:
          "Cannot export replay: the scenario definition is not valid YAML."
      )
    case .ioFailed(let description):
      return String(
        localized: "Failed to write replay file: \(description)")
    }
  }
}

/// Exports a completed simulation into the demo-replay YAML schema
/// (`docs/specs/demo-replay-spec.md` §3.2) for curator ingestion.
///
/// Shipped as part of the Phase 2 E1 "YAML simulation replay primitive"
/// (Issue #167). The same format is consumed by ``YAMLReplaySource``
/// (importer primitive) so round-trip is the defining invariant.
///
/// ContentFilter is applied **at record time** (spec §3.4) to every
/// `fields.*` value and every `code_phase_events[].summary` string.
/// Render-time filtering is the future `ReplayViewModel`'s concern and
/// is out of scope for E1 (#C tracks it).
///
/// `metadata.content_filter_applied` is emitted `false` — spec §3.4
/// reserves the `true` value for curators to set after **manual audit**.
/// Automated ContentFilter application is not sufficient to flip it.
///
/// Marked `nonisolated` so ``YAMLReplaySource`` (also nonisolated, for
/// actor-isolation reasons in `.claude/rules/llm.md`) can reference the
/// shared schema constants. File writing is thread-safe through
/// `FileManager`.
nonisolated struct YAMLReplayExporter {  // swiftlint:disable:this type_body_length
  /// Current on-disk schema version. Must match ``YAMLReplaySource``'s
  /// `supportedSchemaVersion` so round-trip works without a version
  /// negotiation step.
  static let schemaVersion = 1

  /// Output bundle returned to the caller. Mirrors
  /// ``ResultMarkdownExporter/ExportedResult`` so the Share Sheet
  /// plumbing in ``ResultDetailView`` is symmetric.
  struct ExportedResult: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let fileURL: URL
  }

  /// Bundled inputs describing the simulation to export.
  ///
  /// `nonisolated` so callers off the main actor (e.g. an off-main DB
  /// loader) can construct `Input` without hopping to MainActor — same
  /// rationale as ``ResultMarkdownExporter/Input``.
  nonisolated struct Input: Sendable {
    let simulation: SimulationRecord
    let scenario: ScenarioRecord
    let turns: [TurnRecord]
    let codePhaseEvents: [CodePhaseEventRecord]

    init(
      simulation: SimulationRecord,
      scenario: ScenarioRecord,
      turns: [TurnRecord],
      codePhaseEvents: [CodePhaseEventRecord] = []
    ) {
      self.simulation = simulation
      self.scenario = scenario
      self.turns = turns
      self.codePhaseEvents = codePhaseEvents
    }
  }

  private let contentFilter: ContentFilter
  private let now: Date
  private let fileManager: FileManager

  init(
    contentFilter: ContentFilter,
    now: Date = Date(),
    fileManager: FileManager = .default
  ) {
    self.contentFilter = contentFilter
    self.now = now
    self.fileManager = fileManager
  }

  /// Renders the input as demo-replay YAML, writes it to a temp `.yaml`
  /// file, and returns both the text and URL for Share Sheet use.
  func export(_ input: Input) throws -> ExportedResult {
    let yaml = try renderYAML(input)
    let url = try writeToTempFile(yaml: yaml, scenarioId: input.scenario.id)
    return ExportedResult(text: yaml, fileURL: url)
  }

  // MARK: - Rendering

  private func renderYAML(_ input: Input) throws -> String {
    guard let scenario = try? ScenarioLoader().load(yaml: input.scenario.yamlDefinition)
    else {
      throw YAMLReplayExporterError.scenarioYAMLInvalid
    }

    let sortedTurns = input.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
    let sortedEvents = input.codePhaseEvents.sorted { $0.sequenceNumber < $1.sequenceNumber }
    let turnPhaseIndices = Self.resolvePhaseIndices(scenario: scenario, turns: sortedTurns)
    let eventPhaseIndices = Self.resolveEventPhaseIndices(
      scenario: scenario, events: sortedEvents)

    let totalTurns = sortedTurns.filter { $0.agentName != nil }.count
    // Nominal duration at 1× playback using the `demoDefault` pacing.
    // Actual playback time = this / `ReplayPlaybackConfig.speedMultiplier`.
    let pacing = ReplayPlaybackConfig.demoDefault
    let estimatedDurationMs =
      totalTurns * pacing.turnDelayMs
      + sortedEvents.count * pacing.codePhaseDelayMs

    var sections: [String] = []
    sections.append("# Generated by Pastura — demo-replay-spec §3.2")
    sections.append("schema_version: \(Self.schemaVersion)")
    sections.append(renderPresetRef(input: input))
    sections.append(
      renderMetadata(
        input: input, totalTurns: totalTurns,
        estimatedDurationMs: estimatedDurationMs))
    sections.append(renderTurns(turns: sortedTurns, phaseIndices: turnPhaseIndices))
    if !sortedEvents.isEmpty {
      sections.append(
        renderCodePhaseEvents(events: sortedEvents, phaseIndices: eventPhaseIndices))
    }

    return sections.joined(separator: "\n\n") + "\n"
  }

  private func renderPresetRef(input: Input) -> String {
    let sha = Self.sha256Hex(input.scenario.yamlDefinition)
    var lines: [String] = ["preset_ref:"]
    lines.append("  id: \(Self.yamlValue(input.scenario.id))")
    // `version` is informational (spec §3.2). Scenarios in the DB do not
    // track a version field; curator edits the YAML manually to match
    // the shipped preset's convention before bundling.
    lines.append("  version: ''")
    lines.append("  yaml_sha256: \(Self.yamlValue(sha))")
    return lines.joined(separator: "\n")
  }

  private func renderMetadata(
    input: Input, totalTurns: Int, estimatedDurationMs: Int
  ) -> String {
    var lines: [String] = ["metadata:"]
    lines.append("  title: \(Self.yamlValue(input.scenario.name))")
    lines.append("  description: \(Self.yamlValue("", indent: 2))")
    // Phase 2 ship is JA-only (spec §2 decision 12 / §5.5).
    lines.append("  language: ja")
    lines.append("  recorded_at: \(Self.iso8601(now))")
    let model = input.simulation.modelIdentifier ?? ""
    lines.append("  recorded_with_model: \(Self.yamlValue(model))")
    // Spec §3.4: curator flips this to `true` only after MANUAL audit.
    // The exporter has applied ContentFilter but has not performed a
    // human audit, so the emitted value must remain `false`.
    lines.append("  content_filter_applied: false")
    lines.append("  total_turns: \(totalTurns)")
    lines.append("  estimated_duration_ms: \(estimatedDurationMs)")
    lines.append("  captured_by: ''")
    return lines.joined(separator: "\n")
  }

  private func renderTurns(turns: [TurnRecord], phaseIndices: [Int]) -> String {
    guard !turns.isEmpty else { return "turns: []" }
    var lines: [String] = ["turns:"]
    for (idx, turn) in turns.enumerated() {
      guard let agent = turn.agentName else {
        // Pre-#92 legacy rows with nil agentName are not representable
        // in the replay schema (which requires an agent). Skip silently.
        continue
      }
      let phaseIndex = phaseIndices[safe: idx] ?? 0
      lines.append("  - round: \(turn.roundNumber)")
      lines.append("    phase_index: \(phaseIndex)")
      lines.append("    phase_type: \(Self.yamlValue(turn.phaseType))")
      lines.append("    agent: \(Self.yamlValue(agent))")
      let fields = Self.decodeTurnFields(turn, filter: contentFilter)
      lines.append(contentsOf: renderFields(fields, indent: 4))
    }
    return lines.joined(separator: "\n")
  }

  private func renderFields(_ fields: [String: String], indent: Int) -> [String] {
    let base = String(repeating: " ", count: indent)
    let childIndent = indent + 2
    guard !fields.isEmpty else { return ["\(base)fields: {}"] }
    var out: [String] = ["\(base)fields:"]
    for key in fields.keys.sorted() {
      let value = fields[key] ?? ""
      let rendered = Self.yamlValue(value, indent: childIndent)
      out.append("\(String(repeating: " ", count: childIndent))\(key): \(rendered)")
    }
    return out
  }

  private func renderCodePhaseEvents(
    events: [CodePhaseEventRecord], phaseIndices: [Int]
  ) -> String {
    var lines: [String] = ["code_phase_events:"]
    for (idx, event) in events.enumerated() {
      let payload = Self.decodePayload(event)
      let summary = Self.summary(for: payload, filter: contentFilter)
      let phaseIndex = phaseIndices[safe: idx] ?? 0
      lines.append("  - round: \(event.roundNumber)")
      lines.append("    phase_index: \(phaseIndex)")
      lines.append("    phase_type: \(Self.yamlValue(event.phaseType))")
      lines.append("    summary: \(Self.yamlValue(summary, indent: 4))")
      lines.append(contentsOf: renderPayloadStanza(payload, filter: contentFilter))
    }
    return lines.joined(separator: "\n")
  }

  /// Serialises a ``CodePhaseEventPayload`` as a `payload:` stanza with
  /// a `kind` discriminator. Added in E1 beyond the spec §3.2 example
  /// so structured payloads survive round-trip — the bare `summary:`
  /// field would force #C to parse narrative strings back into structured
  /// data, which is lossy by construction.
  private func renderPayloadStanza(
    _ payload: CodePhaseEventPayload?, filter: ContentFilter
  ) -> [String] {
    guard let payload else {
      return ["    payload:", "      kind: unknown"]
    }
    var lines: [String] = ["    payload:"]
    switch payload {
    case .elimination(let agent, let voteCount):
      lines.append("      kind: elimination")
      lines.append("      agent: \(Self.yamlValue(agent))")
      lines.append("      vote_count: \(voteCount)")
    case .scoreUpdate(let scores):
      lines.append("      kind: scoreUpdate")
      lines.append(contentsOf: renderStringIntMap("scores", map: scores, indent: 6))
    case .summary(let text):
      lines.append("      kind: summary")
      // Text already lives in the top-level `summary:` field; repeating
      // here would bloat the file. Intentionally omitted.
      _ = text
    case .voteResults(let votes, let tallies):
      lines.append("      kind: voteResults")
      lines.append(contentsOf: renderStringStringMap("votes", map: votes, indent: 6))
      lines.append(contentsOf: renderStringIntMap("tallies", map: tallies, indent: 6))
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      lines.append("      kind: pairingResult")
      lines.append("      agent1: \(Self.yamlValue(agent1))")
      lines.append("      action1: \(Self.yamlValue(filter.filter(action1)))")
      lines.append("      agent2: \(Self.yamlValue(agent2))")
      lines.append("      action2: \(Self.yamlValue(filter.filter(action2)))")
    case .assignment(let agent, let value):
      lines.append("      kind: assignment")
      lines.append("      agent: \(Self.yamlValue(agent))")
      lines.append("      value: \(Self.yamlValue(filter.filter(value)))")
    }
    return lines
  }

  private func renderStringIntMap(
    _ label: String, map: [String: Int], indent: Int
  ) -> [String] {
    let base = String(repeating: " ", count: indent)
    guard !map.isEmpty else { return ["\(base)\(label): {}"] }
    var out: [String] = ["\(base)\(label):"]
    for key in map.keys.sorted() {
      let value = map[key] ?? 0
      out.append(
        "\(String(repeating: " ", count: indent + 2))\(Self.yamlKey(key)): \(value)")
    }
    return out
  }

  private func renderStringStringMap(
    _ label: String, map: [String: String], indent: Int
  ) -> [String] {
    let base = String(repeating: " ", count: indent)
    guard !map.isEmpty else { return ["\(base)\(label): {}"] }
    var out: [String] = ["\(base)\(label):"]
    let childIndent = indent + 2
    for key in map.keys.sorted() {
      let value = map[key] ?? ""
      out.append(
        "\(String(repeating: " ", count: childIndent))"
          + "\(Self.yamlKey(key)): \(Self.yamlValue(value, indent: childIndent))")
    }
    return out
  }

  // MARK: - Phase index resolution

  /// Linear walk through `scenario.phases` to resolve each turn's
  /// `phase_index`. Advances a per-round cursor each time the observed
  /// `phaseType` changes.
  ///
  /// **Limitations (documented, E1 scope):**
  /// - Two adjacent phases of the same type within one round collapse to
  ///   the first matching index — the cursor can't tell them apart.
  /// - Turns produced by sub-phases inside a `conditional` resolve to
  ///   the outer conditional's index; the denormalised `phase_type` in
  ///   the emitted YAML will then mismatch `phases[phase_index].type`
  ///   and fail a strict consistency check.
  ///
  /// The `phasePathJSON` column landed in #143 so `TurnRecord.phasePath`
  /// now carries exact lineage (e.g. `[1, 0]` for a sub-phase). This
  /// resolver still ignores it because the YAML replay schema's
  /// `phase_index: Int` is a flat top-level index, not a path — teaching
  /// the schema to represent nested addresses is a separate piece of
  /// work. For now, the cursor keeps the Phase 2 presets (Word Wolf,
  /// Prisoner's Dilemma) round-tripping correctly; conditional-heavy
  /// scenarios hit the documented limitations. Upgrading the schema and
  /// switching to `phasePath`-aware resolution is tracked as a follow-up.
  private static func resolvePhaseIndices(
    scenario: Scenario, turns: [TurnRecord]
  ) -> [Int] {
    var result: [Int] = []
    var cursorByRound: [Int: Int] = [:]
    var lastTypeByRound: [Int: String] = [:]
    for turn in turns {
      let round = turn.roundNumber
      var cursor = cursorByRound[round] ?? -1
      let lastType = lastTypeByRound[round]
      if turn.phaseType != lastType {
        cursor = advanceCursor(
          from: cursor, matching: turn.phaseType, in: scenario.phases)
        cursorByRound[round] = cursor
        lastTypeByRound[round] = turn.phaseType
      }
      result.append(max(cursor, 0))
    }
    return result
  }

  private static func resolveEventPhaseIndices(
    scenario: Scenario, events: [CodePhaseEventRecord]
  ) -> [Int] {
    events.map { event in
      if let idx = scenario.phases.firstIndex(where: {
        $0.type.rawValue == event.phaseType
      }) {
        return idx
      }
      // Not a top-level phase — the event originated inside a
      // `conditional`'s branch (e.g. `summarize` used in then/else).
      // `event.phasePath` (persisted since #143) has the exact inner
      // location, but the YAML replay schema's `phase_index` is flat,
      // so we still fall back to the conditional's index here and let
      // the schema upgrade lift this when it lands.
      return conditionalFallbackIndex(in: scenario.phases)
    }
  }

  private static func advanceCursor(
    from current: Int, matching type: String, in phases: [Phase]
  ) -> Int {
    var next = current + 1
    while next < phases.count && phases[next].type.rawValue != type {
      next += 1
    }
    if next < phases.count { return next }
    // Fell off the end — try the first matching index anywhere
    // (repeated-same-type case), then fall back to the conditional's
    // index (sub-phase case), then finally preserve the last-known
    // cursor.
    if let anyMatch = phases.firstIndex(where: { $0.type.rawValue == type }) {
      return anyMatch
    }
    return conditionalFallbackIndex(in: phases, defaultingTo: max(current, 0))
  }

  /// Shared fallback for both turn and code-phase-event `phase_index`
  /// resolution when the observed `phase_type` is not a top-level
  /// phase. Points at the outer `conditional` so the enclosing phase
  /// context is preserved; consumers that want the exact sub-phase
  /// wait for the future `phaseIndex` column migration.
  private static func conditionalFallbackIndex(
    in phases: [Phase], defaultingTo fallback: Int = 0
  ) -> Int {
    phases.firstIndex { $0.type == .conditional } ?? fallback
  }

  // MARK: - Payload + summary helpers

  private static func decodeTurnFields(
    _ turn: TurnRecord, filter: ContentFilter
  ) -> [String: String] {
    guard
      let data = turn.parsedOutputJSON.data(using: .utf8),
      let output = try? JSONDecoder().decode(TurnOutput.self, from: data)
    else {
      return [:]
    }
    return output.fields.mapValues { filter.filter($0) }
  }

  private static func decodePayload(
    _ record: CodePhaseEventRecord
  ) -> CodePhaseEventPayload? {
    guard let data = record.payloadJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(CodePhaseEventPayload.self, from: data)
  }

  /// Human-readable one-line summary for a code-phase payload. Pattern
  /// mirrors ``ResultMarkdownExporter/renderCodePhasePayload(_:)`` so
  /// the YAML reads the same way the Markdown export does.
  private static func summary(
    for payload: CodePhaseEventPayload?, filter: ContentFilter
  ) -> String {
    guard let payload else { return "" }
    switch payload {
    case .elimination(let agent, let voteCount):
      return "\(agent) was eliminated (\(voteCount) votes)"
    case .scoreUpdate(let scores):
      let ordered = scores.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
      }
      let pairs = ordered.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      return "Scores — \(pairs)"
    case .summary(let text):
      return filter.filter(text)
    case .voteResults(_, let tallies):
      let ordered = tallies.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
      }
      let pairs = ordered.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      return "Votes — \(pairs)"
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      let filtered1 = filter.filter(action1)
      let filtered2 = filter.filter(action2)
      return "\(agent1) (\(filtered1)) ↔ \(agent2) (\(filtered2))"
    case .assignment(let agent, let value):
      return "\(agent) was assigned: \(filter.filter(value))"
    }
  }

  // MARK: - YAML emission primitives

  /// Emits a YAML key. Single-quoted unless the key is already a safe
  /// bare identifier — matches curator expectations for bundled YAMLs.
  static func yamlKey(_ key: String) -> String {
    if key.isEmpty { return "''" }
    // Safe bare: starts with letter/underscore, contains only
    // letters/digits/underscore/hyphen. Avoids YAML reserved words
    // by quoting numeric-looking keys and booleans.
    if isSafeBareIdentifier(key) { return key }
    return singleQuoted(key)
  }

  /// Emits a YAML value (single-line form — caller's responsibility to
  /// avoid calling from a scalar-only context for very long values).
  static func yamlValue(_ text: String) -> String {
    yamlValue(text, indent: 0)
  }

  /// Emits a YAML value, selecting the safest scalar form for `text`.
  ///
  /// - Empty → `''`
  /// - Contains `\n` → block literal `|` (or `|-`) with `indent + 2`
  ///   continuation indent.
  /// - Contains control chars (`\t`, `\r`, C0 except `\n`) → double-quoted
  ///   with escapes, preserving round-trip through Yams.load.
  /// - Else → single-quoted. Single-quoted is the safest form for
  ///   arbitrary UTF-8 (Japanese, emoji, punctuation) because only
  ///   `'` needs escaping.
  static func yamlValue(_ text: String, indent: Int) -> String {
    if text.isEmpty { return "''" }
    if text.contains("\n") { return blockScalar(text, baseIndent: indent) }
    if containsControlChars(text) { return doubleQuoted(text) }
    return singleQuoted(text)
  }

  private static func singleQuoted(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "'", with: "''")
    return "'\(escaped)'"
  }

  private static func doubleQuoted(_ text: String) -> String {
    var escaped = ""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\\": escaped += "\\\\"
      case "\"": escaped += "\\\""
      case "\n": escaped += "\\n"
      case "\r": escaped += "\\r"
      case "\t": escaped += "\\t"
      case "\0": escaped += "\\0"
      default:
        if scalar.value < 0x20 {
          escaped += String(format: "\\x%02X", scalar.value)
        } else {
          escaped.append(String(scalar))
        }
      }
    }
    return "\"\(escaped)\""
  }

  private static func blockScalar(_ text: String, baseIndent: Int) -> String {
    // `|` (clip) keeps one trailing newline; `|-` (strip) keeps none.
    // Match the input so round-trip preserves trailing-newline presence.
    let indicator = text.hasSuffix("\n") ? "|" : "|-"
    let bodyIndent = String(repeating: " ", count: baseIndent + 2)
    var lines = text.components(separatedBy: "\n")
    if text.hasSuffix("\n") {
      // `components(separatedBy:)` gives a trailing empty string; drop it
      // so we don't emit a blank line that `|` would preserve.
      lines = Array(lines.dropLast())
    }
    let body = lines.map { bodyIndent + $0 }.joined(separator: "\n")
    return "\(indicator)\n\(body)"
  }

  private static func containsControlChars(_ text: String) -> Bool {
    for scalar in text.unicodeScalars
    where scalar.value < 0x20 && scalar.value != 0x0A {
      return true
    }
    return false
  }

  private static func isSafeBareIdentifier(_ key: String) -> Bool {
    guard let first = key.first else { return false }
    let firstOK = first.isLetter || first == "_"
    if !firstOK { return false }
    for char in key
    where !(char.isLetter || char.isNumber || char == "_" || char == "-") {
      return false
    }
    // Avoid YAML reserved words.
    let reserved: Set<String> = [
      "true", "false", "null", "yes", "no", "on", "off", "True", "False",
      "Null", "Yes", "No", "On", "Off", "TRUE", "FALSE", "NULL", "YES", "NO",
      "ON", "OFF", "~"
    ]
    return !reserved.contains(key)
  }

  // MARK: - SHA-256

  /// Exporter-side alias for ``ReplayHashing/sha256Hex(_:)``.
  ///
  /// Both sides of the spec §3.3 drift guard (exporter producing
  /// `preset_ref.yaml_sha256`, resolver re-hashing the shipped preset
  /// YAML at load time) **must** use the same algorithm on the same
  /// bytes — see ``ReplayHashing`` for the invariant. Keeping this
  /// alias lets existing callers stay byte-identical while the
  /// implementation lives in one place.
  static func sha256Hex(_ source: String) -> String {
    ReplayHashing.sha256Hex(source)
  }

  // MARK: - Date formatting

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  // MARK: - File writing

  private func writeToTempFile(yaml: String, scenarioId: String) throws -> URL {
    let sanitized = Self.sanitizeFilename(scenarioId)
    let timestamp = Self.filenameTimestamp.string(from: now)
    let filename = "\(sanitized)_replay_\(timestamp).yaml"
    let url = fileManager.temporaryDirectory.appendingPathComponent(filename)
    do {
      try yaml.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      throw YAMLReplayExporterError.ioFailed(description: error.localizedDescription)
    }
    return url
  }

  /// Public so tests (and the future wrapper sources) can reproduce the
  /// rule without depending on ``ResultMarkdownExporter``.
  static func sanitizeFilename(_ name: String) -> String {
    let allowed =
      CharacterSet.letters.union(.decimalDigits).union(
        CharacterSet(charactersIn: "_-"))
    let mapped = name.unicodeScalars.map {
      allowed.contains($0) ? Character($0) : "_"
    }
    let collapsed = String(mapped)
    let trimmed = collapsed.isEmpty ? "replay" : collapsed
    return String(trimmed.prefix(50))
  }

  private static let filenameTimestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}

// MARK: - Safe-subscript helper

extension Array {
  nonisolated fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
