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
struct ResultMarkdownExporter {
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
  struct Input {
    let simulation: SimulationRecord
    let scenario: ScenarioRecord
    let turns: [TurnRecord]
    let state: SimulationState
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
    if hasMeaningfulScoreData(input.state) {
      sections.append(renderFinalScores(input))
    }
    return sections.joined(separator: "\n\n") + "\n"
  }

  // Observation-only scenarios (e.g. pure speak_each / Asch conformity) have
  // no scoring phase — state.scores is still initialized with 0 per agent, so
  // suppressing the "Final Scores" section requires a semantic check rather
  // than an emptiness check.
  private func hasMeaningfulScoreData(_ state: SimulationState) -> Bool {
    state.scores.values.contains(where: { $0 != 0 })
      || state.eliminated.values.contains(true)
      || !state.voteResults.isEmpty
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

  private func renderTurnLog(_ input: Input) -> String {
    guard !input.turns.isEmpty else {
      return "## Turn Log\n\n_No turns recorded._"
    }

    var lines: [String] = ["## Turn Log"]
    // Group turns by round while preserving sequenceNumber order within each round.
    let sorted = input.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
    let grouped = Dictionary(grouping: sorted, by: { $0.roundNumber })
    for round in grouped.keys.sorted() {
      lines.append("")
      lines.append("### Round \(round)")
      let turnsInRound = grouped[round] ?? []
      // Group by phase within round, preserving first-seen order.
      var phaseOrder: [String] = []
      var byPhase: [String: [TurnRecord]] = [:]
      for turn in turnsInRound {
        if byPhase[turn.phaseType] == nil {
          phaseOrder.append(turn.phaseType)
          byPhase[turn.phaseType] = []
        }
        byPhase[turn.phaseType]?.append(turn)
      }
      for phase in phaseOrder {
        lines.append("")
        lines.append("#### Phase: \(phase)")
        for turn in byPhase[phase] ?? [] {
          lines.append(renderTurnLine(turn))
        }
      }
    }
    return lines.joined(separator: "\n")
  }

  private func renderTurnLine(_ turn: TurnRecord) -> String {
    guard let agent = turn.agentName else {
      // Code phase turn — no agent, no LLM output to render. Emit a placeholder
      // so the phase's presence is still visible in the log.
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

  private func decodeOutput(_ turn: TurnRecord) -> TurnOutput {
    guard
      let data = turn.parsedOutputJSON.data(using: .utf8),
      let output = try? JSONDecoder().decode(TurnOutput.self, from: data)
    else {
      return TurnOutput(fields: [:])
    }
    return output
  }

  // Picks the most natural field for display per phase. Falls back to a JSON
  // dump of all fields if none of the common ones are present — keeps unknown
  // phase types readable without requiring exporter changes.
  private func formatOutput(_ output: TurnOutput, phaseType: String) -> String {
    if let statement = output.statement, !statement.isEmpty { return statement }
    if let vote = output.vote, !vote.isEmpty { return "→ \(vote)" }
    if let action = output.action, !action.isEmpty { return "(action: \(action))" }
    if let declaration = output.declaration, !declaration.isEmpty { return declaration }
    if output.fields.isEmpty { return "_(empty)_" }
    let pairs = output.fields.keys.sorted().map { "\($0)=\(output.fields[$0] ?? "")" }
    return pairs.joined(separator: ", ")
  }

  private func renderFinalScores(_ input: Input) -> String {
    let scores = input.state.scores
    guard !scores.isEmpty else {
      return "## Final Scores\n\n_No score data._"
    }
    var lines: [String] = [
      "## Final Scores", "", "| Agent | Score | Status |", "|-------|-------|--------|"
    ]
    let ordered = scores.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return lhs.key < rhs.key
    }
    for (agent, score) in ordered {
      let eliminated = input.state.eliminated[agent] == true
      let status = eliminated ? "eliminated" : "active"
      lines.append("| \(agent) | \(score) | \(status) |")
    }
    return lines.joined(separator: "\n")
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
