// swiftlint:disable file_length
import Foundation

/// Formats a completed simulation into a Markdown document for external sharing
/// (Claude analysis, SNS, experiment logging) and writes it to a temp file URL.
///
/// The exporter is intentionally a `@MainActor`-default type in the App layer
/// — it composes records produced on background threads with `ContentFilter`
/// (also App-layer), and is invoked from SwiftUI views. For long renders, call
/// it inside `offMain { ... }` from the caller side.
///
/// ContentFilter is applied as a **whole-string pass** on the final rendered
/// Markdown, not per-field, so YAML content, persona names, and conversation
/// log prose are all covered in one sweep.
struct ResultMarkdownExporter {  // swiftlint:disable:this type_body_length
  /// Environment metadata captured at export time.
  struct ExportEnvironment: Sendable {
    /// `UIDevice.current.model` value (e.g. "iPhone").
    let deviceModel: String
    /// Normalized OS version string — `"iOS 26.4 (build 23E246)"` style.
    /// Apply `normalizeOSVersion(_:)` to the raw
    /// `ProcessInfo.operatingSystemVersionString` before constructing.
    let osVersion: String

    /// Rewrites Apple's `"Version X.Y (Build ABC)"` into `"iOS X.Y (build ABC)"`
    /// so exported metadata reads naturally. Safe on strings that don't match
    /// the pattern — they pass through unchanged.
    static func normalizeOSVersion(_ raw: String) -> String {
      raw.replacingOccurrences(of: "Version ", with: "iOS ")
        .replacingOccurrences(of: "(Build ", with: "(build ")
    }
  }

  /// The exporter's output — both the Markdown text and a temp-file URL for
  /// sharing. `Identifiable` so it can drive `.sheet(item:)` directly.
  struct ExportedResult: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let fileURL: URL
  }

  /// Bundled inputs describing the simulation to export.
  ///
  /// `nonisolated` so callers off the main actor (e.g. the background
  /// export assemblers) can construct `Input` without hopping to MainActor.
  /// Pure data — no isolated state.
  nonisolated struct Input: Sendable {
    let simulation: SimulationRecord
    let scenario: ScenarioRecord
    let turns: [TurnRecord]
    let codePhaseEvents: [CodePhaseEventRecord]
    /// Agent name roster used for the Final Scores / Roster Status section.
    /// Authoritative over code-phase event contents — events may omit agents
    /// that never scored, but every persona should appear in the roster.
    let personas: [String]
    let state: SimulationState

    init(
      simulation: SimulationRecord,
      scenario: ScenarioRecord,
      turns: [TurnRecord],
      codePhaseEvents: [CodePhaseEventRecord] = [],
      personas: [String] = [],
      state: SimulationState
    ) {
      self.simulation = simulation
      self.scenario = scenario
      self.turns = turns
      self.codePhaseEvents = codePhaseEvents
      self.personas = personas
      self.state = state
    }
  }

  private let contentFilter: ContentFilter
  private let environment: ExportEnvironment
  private let now: Date
  private let fileManager: FileManager

  init(
    contentFilter: ContentFilter,
    environment: ExportEnvironment,
    now: Date = Date(),
    fileManager: FileManager = .default
  ) {
    self.contentFilter = contentFilter
    self.environment = environment
    self.now = now
    self.fileManager = fileManager
  }

  /// Renders the input as Markdown, applies `ContentFilter`, writes to a temp
  /// `.md` file, and returns both the text and URL.
  func export(_ input: Input) throws -> ExportedResult {
    let raw = renderMarkdown(input)
    let filtered = contentFilter.filter(raw)
    let url = try writeToTempFile(text: filtered, scenarioName: input.scenario.name)
    return ExportedResult(text: filtered, fileURL: url)
  }

  // MARK: - Rendering

  private func renderMarkdown(_ input: Input) -> String {
    var sections: [String] = []
    sections.append("<!-- pastura-export v1 -->")
    sections.append("# Simulation Export: \(input.scenario.name)")
    sections.append(renderMetadata(input))
    sections.append(renderScenarioYAML(input))
    sections.append(renderTurnLog(input))

    // Bifurcated final-section gating (events are authoritative; the section
    // is independent of `SimulationState.scores` so it stays correct even when
    // `stateJSON` has not been kept in sync during the run).
    // - scoreUpdate event present → Final Scores table (scores + status).
    // - elimination event present only → Roster Status (status-only, no
    //   misleading all-zero score table for scenarios like Word Wolf).
    // - neither → omit entirely (observation-only scenarios).
    let payloads = decodedPayloads(input.codePhaseEvents)
    let hasScoreUpdate = payloads.contains { payload in
      if case .scoreUpdate = payload { return true }
      return false
    }
    let hasElimination = payloads.contains { payload in
      if case .elimination = payload { return true }
      return false
    }
    if hasScoreUpdate {
      sections.append(renderFinalScores(input, payloads: payloads))
    } else if hasElimination {
      sections.append(renderRosterStatus(input, payloads: payloads))
    }
    return sections.joined(separator: "\n\n") + "\n"
  }

  private func renderMetadata(_ input: Input) -> String {
    let sim = input.simulation
    let status = sim.simulationStatus?.rawValue ?? sim.status
    let started = Self.isoFormatter.string(from: sim.createdAt)
    let ended = Self.isoFormatter.string(from: sim.updatedAt)
    let duration = formatDuration(sim.updatedAt.timeIntervalSince(sim.createdAt))
    let model = sim.modelIdentifier ?? "(unknown)"
    let backend = sim.llmBackend ?? "(unknown)"
    let inferenceCount = input.turns.filter { $0.agentName != nil }.count

    return """
      ## Metadata

      - **Scenario**: \(input.scenario.name) (`\(input.scenario.id)`)
      - **Status**: \(status)
      - **Started**: \(started)
      - **Ended**: \(ended)
      - **Duration**: \(duration)
      - **Model**: \(model)
      - **Backend**: \(backend)
      - **Device**: \(environment.deviceModel) / \(environment.osVersion)
      - **Inference count**: \(inferenceCount)
      """
  }

  private func renderScenarioYAML(_ input: Input) -> String {
    """
    ## Scenario Definition

    ```yaml
    \(input.scenario.yamlDefinition)
    ```
    """
  }

  /// Unified timeline item for merge-sorted rendering. `TurnRecord` and
  /// `CodePhaseEventRecord` share `sequenceNumber` across both tables, so
  /// combining them restores the original event arrival order.
  private enum TimelineItem {
    case turn(TurnRecord)
    case codePhase(CodePhaseEventRecord, CodePhaseEventPayload)

    var round: Int {
      switch self {
      case .turn(let turn): return turn.roundNumber
      case .codePhase(let record, _): return record.roundNumber
      }
    }
    var sequenceNumber: Int {
      switch self {
      case .turn(let turn): return turn.sequenceNumber
      case .codePhase(let record, _): return record.sequenceNumber
      }
    }
    var phaseType: String {
      switch self {
      case .turn(let turn): return turn.phaseType
      case .codePhase(let record, _): return record.phaseType
      }
    }
    /// `nil` for legacy rows (pre-v6) and top-level phases; `[K, N, ...]` for nested
    /// sub-phases inside a conditional. Mirrors the underlying record's `phasePath`.
    var phasePath: [Int]? {
      switch self {
      case .turn(let turn): return turn.phasePath
      case .codePhase(let record, _): return record.phasePath
      }
    }
  }

  /// Groups timeline items within a round. Legacy rows (`phasePath == nil`) and
  /// top-level rows (`phasePath.count == 1`) collapse into one block per phaseType
  /// to preserve the mixed-era invariant. Nested sub-phase rows (`phasePath.count > 1`)
  /// each get their own block keyed on the exact path so sibling conditional branches
  /// appear separately.
  private enum PhaseGroupKey: Hashable {
    case topLevel(phaseType: String)
    case nested(path: [Int], phaseType: String)

    init(_ item: TimelineItem) {
      let path = item.phasePath
      if let path, path.count > 1 {
        self = .nested(path: path, phaseType: item.phaseType)
      } else {
        self = .topLevel(phaseType: item.phaseType)
      }
    }

    /// Markdown heading for this group.
    var heading: String {
      switch self {
      case .topLevel(let phaseType):
        return "#### Phase: \(phaseType)"
      case .nested(let path, let phaseType):
        let formatted = path.map { String($0) }.joined(separator: ", ")
        return "#### Sub-phase: \(phaseType) (path [\(formatted)])"
      }
    }
  }

  private func renderTurnLog(_ input: Input) -> String {
    // Build a unified timeline. Within a `(round, PhaseGroupKey)` group, items
    // render strictly by ascending `sequenceNumber` — agent votes always
    // precede the tally line under the same heading.
    var timeline: [TimelineItem] = input.turns.map { .turn($0) }
    timeline.append(
      contentsOf: input.codePhaseEvents.map { record in
        if let payload = decodePayload(record) {
          return TimelineItem.codePhase(record, payload)
        }
        // Defensive: unknown payload shape shouldn't happen, but if it does
        // we skip silently rather than crash the export.
        return TimelineItem.codePhase(record, .summary(text: "(unreadable payload)"))
      })
    timeline.sort { $0.sequenceNumber < $1.sequenceNumber }

    guard !timeline.isEmpty else {
      return "## Turn Log\n\n_No turns recorded._"
    }

    var lines: [String] = ["## Turn Log"]
    let grouped = Dictionary(grouping: timeline, by: { $0.round })
    for round in grouped.keys.sorted() {
      lines.append("")
      lines.append("### Round \(round)")
      let itemsInRound = (grouped[round] ?? [])
        .sorted { $0.sequenceNumber < $1.sequenceNumber }
      // Group by PhaseGroupKey within round, preserving first-seen order.
      var keyOrder: [PhaseGroupKey] = []
      var byKey: [PhaseGroupKey: [TimelineItem]] = [:]
      for item in itemsInRound {
        let key = PhaseGroupKey(item)
        if byKey[key] == nil {
          keyOrder.append(key)
          byKey[key] = []
        }
        byKey[key]?.append(item)
      }
      for key in keyOrder {
        lines.append("")
        lines.append(key.heading)
        for item in byKey[key] ?? [] {
          lines.append(render(item))
        }
      }
    }
    return lines.joined(separator: "\n")
  }

  private func render(_ item: TimelineItem) -> String {
    switch item {
    case .turn(let turn):
      return renderTurnLine(turn)
    case .codePhase(_, let payload):
      return renderCodePhasePayload(payload)
    }
  }

  private func renderTurnLine(_ turn: TurnRecord) -> String {
    guard let agent = turn.agentName else {
      // Legacy fallback: a TurnRecord without an agent can only appear in
      // pre-#92 databases that never existed in practice. Emit a placeholder
      // so any stray row doesn't render as a blank bullet.
      return "- _(code phase — no agent output)_"
    }
    let output = decodeOutput(turn)
    let content = formatOutput(output, phaseType: turn.phaseType)
    var line = "- **\(agent)**: \(content)"
    // Include inner_thought as a nested bullet — the gap between outward
    // behavior and inner reasoning is often the most analyzable signal in a
    // multi-agent run (e.g. Asch-style conformity).
    if let thought = output.innerThought, !thought.isEmpty {
      line += "\n  - 💭 _\(thought)_"
    }
    return line
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func renderCodePhasePayload(_ payload: CodePhaseEventPayload) -> String {
    switch payload {
    case .elimination(let agent, let voteCount):
      return "- **\(agent)** was eliminated (\(voteCount) votes)"
    case .scoreUpdate(let scores):
      let ordered = scores.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
      }
      let pairs = ordered.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      return "- Scores — \(pairs)"
    case .summary(let text):
      return "- \(text)"
    case .voteResults(let votes, let tallies):
      var lines: [String] = []
      lines.append("- Tallies:")
      lines.append("")
      lines.append("  | Candidate | Votes |")
      lines.append("  |-----------|-------|")
      let orderedTallies = tallies.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
      }
      for (candidate, count) in orderedTallies {
        lines.append("  | \(candidate) | \(count) |")
      }
      lines.append("")
      lines.append("- Votes:")
      let orderedVotes = votes.sorted { $0.key < $1.key }
      for (voter, target) in orderedVotes {
        lines.append("  - \(voter) → \(target)")
      }
      return lines.joined(separator: "\n")
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      return "- **\(agent1)** (\(action1)) ↔ **\(agent2)** (\(action2))"
    case .assignment(let agent, let value):
      return "- **\(agent)** was assigned: \(value)"
    case .eventInjected(let event):
      // Past results need to surface the miss explicitly so a reader
      // can tell whether the phase ran at all.
      if let event {
        return "- 🎲 Event: \(event)"
      }
      return "- 🎲 No event this round"
    }
  }

  private func decodePayload(_ record: CodePhaseEventRecord) -> CodePhaseEventPayload? {
    guard let data = record.payloadJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(CodePhaseEventPayload.self, from: data)
  }

  private func decodedPayloads(
    _ records: [CodePhaseEventRecord]
  ) -> [CodePhaseEventPayload] {
    records.compactMap { decodePayload($0) }
  }

  private func decodeOutput(_ turn: TurnRecord) -> TurnOutput {
    guard
      let data = turn.parsedOutputJSON.data(using: .utf8),
      let output = try? JSONDecoder().decode(TurnOutput.self, from: data)
    else {
      return TurnOutput(fields: [:])
    }
    return output
  }

  // Picks the canonical primary field per phase via
  // `TurnOutput.primaryText(for:)` (keyed by `ScenarioConventions`). Falls
  // back to a JSON dump of all fields when the canonical field is missing
  // or the phase type is unknown (e.g. forward-compat with future phase
  // types added to TurnRecord without exporter changes).
  private func formatOutput(_ output: TurnOutput, phaseType: String) -> String {
    if let pt = PhaseType(rawValue: phaseType),
      let primary = output.primaryText(for: pt),
      !primary.isEmpty {
      return primary
    }
    if output.fields.isEmpty { return "_(empty)_" }
    let pairs = output.fields.keys.sorted().map { "\($0)=\(output.fields[$0] ?? "")" }
    return pairs.joined(separator: ", ")
  }

  /// Renders "Final Scores" from the latest `.scoreUpdate` payload merged
  /// onto the persona roster. Agents not present in the payload default to
  /// 0 — the roster is authoritative so the table always covers all personas.
  ///
  /// Events are the source of truth here, independent of
  /// `SimulationState.stateJSON`. This stays correct even if continuous
  /// state persistence (pause/resume) lands later — events are append-only,
  /// state is just a snapshot.
  private func renderFinalScores(
    _ input: Input, payloads: [CodePhaseEventPayload]
  ) -> String {
    let latestScores = latestScoreUpdate(in: payloads)
    let eliminatedSet = eliminatedAgents(in: payloads)
    let roster = rosterAgents(input: input, latestScores: latestScores)

    guard !roster.isEmpty else {
      return "## Final Scores\n\n_No score data._"
    }

    var lines: [String] = [
      "## Final Scores", "", "| Agent | Score | Status |", "|-------|-------|--------|"
    ]
    // Sort by score desc, then by name asc for deterministic output.
    let ordered = roster.sorted { lhs, rhs in
      let lhsScore = latestScores[lhs] ?? 0
      let rhsScore = latestScores[rhs] ?? 0
      if lhsScore != rhsScore { return lhsScore > rhsScore }
      return lhs < rhs
    }
    for agent in ordered {
      let score = latestScores[agent] ?? 0
      let status = eliminatedSet.contains(agent) ? "eliminated" : "active"
      lines.append("| \(agent) | \(score) | \(status) |")
    }
    return lines.joined(separator: "\n")
  }

  /// Renders "Roster Status" when elimination events exist but no score
  /// updates were emitted (e.g., Word Wolf — `wordwolf_judge` announces the
  /// winner via `.summary` and drops elimination events without a score
  /// delta). Shows active/eliminated per persona without a misleading
  /// all-zero score column.
  private func renderRosterStatus(
    _ input: Input, payloads: [CodePhaseEventPayload]
  ) -> String {
    let eliminatedSet = eliminatedAgents(in: payloads)
    let roster = rosterAgents(input: input, latestScores: [:])

    guard !roster.isEmpty else {
      return "## Roster Status\n\n_No roster data._"
    }

    var lines: [String] = [
      "## Roster Status", "", "| Agent | Status |", "|-------|--------|"
    ]
    // Eliminated agents first (narrative interest), then by name.
    let ordered = roster.sorted { lhs, rhs in
      let lElim = eliminatedSet.contains(lhs)
      let rElim = eliminatedSet.contains(rhs)
      if lElim != rElim { return lElim && !rElim }
      return lhs < rhs
    }
    for agent in ordered {
      let status = eliminatedSet.contains(agent) ? "eliminated" : "active"
      lines.append("| \(agent) | \(status) |")
    }
    return lines.joined(separator: "\n")
  }

  private func latestScoreUpdate(
    in payloads: [CodePhaseEventPayload]
  ) -> [String: Int] {
    // payloads are in event-arrival order (caller passes `decodedPayloads`
    // which preserves the fetched order, and the repository orders by
    // sequenceNumber). The last scoreUpdate is authoritative for final values.
    for payload in payloads.reversed() {
      if case .scoreUpdate(let scores) = payload { return scores }
    }
    return [:]
  }

  private func eliminatedAgents(
    in payloads: [CodePhaseEventPayload]
  ) -> Set<String> {
    var agents: Set<String> = []
    for payload in payloads {
      if case .elimination(let agent, _) = payload { agents.insert(agent) }
    }
    return agents
  }

  /// Union of `input.personas` and agents that appear in `latestScores`.
  /// `input.personas` is authoritative; extra scored agents are included
  /// defensively so a broken roster never hides data.
  private func rosterAgents(
    input: Input, latestScores: [String: Int]
  ) -> [String] {
    var set = Set(input.personas)
    set.formUnion(latestScores.keys)
    return Array(set)
  }

  // MARK: - Duration formatting

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds.rounded()), 0)
    let minutes = total / 60
    let secs = total % 60
    if minutes == 0 { return "\(secs)s" }
    return "\(minutes)m \(secs)s"
  }

  // MARK: - File writing

  private func writeToTempFile(text: String, scenarioName: String) throws -> URL {
    let sanitized = Self.sanitizeFilename(scenarioName)
    let timestamp = Self.timestampFormatter.string(from: now)
    let filename = "\(sanitized)_\(timestamp).md"
    let url = fileManager.temporaryDirectory.appendingPathComponent(filename)
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  /// Public so tests can validate the rule directly.
  static func sanitizeFilename(_ name: String) -> String {
    // Keep Unicode letters/digits, underscore, and hyphen; replace anything else
    // with underscore so Japanese / emoji scenario names produce usable filenames.
    let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_-"))
    let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let collapsed = String(mapped)
    let trimmed = collapsed.isEmpty ? "export" : collapsed
    // Cap length to keep temp paths reasonable on all filesystems.
    return String(trimmed.prefix(50))
  }

  // MARK: - Formatters

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}
