// swiftlint:disable file_length
// Deliberately long: YAMLReplaySource owns YAML loading, the compiled-plan
// data model, planning for both `turns` and `code_phase_events`, and the
// paced-plan emission consumed by `ReplayViewModel`. The fileprivate YAML
// parsing helpers and per-section planners share the same `Compiled` plan
// shape — splitting would force these helpers to module scope and weaken
// the spec §3.5 "silent skip on unknown schema_version" boundary. See
// YAMLReplayExporter.swift (the reverse direction of the same round-trip)
// for the same pattern.
import Foundation
import Yams

/// Errors produced by ``YAMLReplaySource``.
///
/// Spec §3.5 mandates "silent skip" on unknown `schema_version`. That
/// policy is enforced by the **wrapper** source (future
/// `BundledDemoReplaySource`, #C), not the primitive — callers
/// implementing user-visible replay flows can surface the same errors
/// as actionable diagnostics instead of swallowing them.
nonisolated public enum YAMLReplaySourceError: Error, Equatable {
  /// The YAML could not be parsed as a mapping.
  case malformedYAML(description: String)
  /// Present but not equal to ``YAMLReplayExporter/schemaVersion``.
  /// `nil` means the `schema_version` key was missing entirely.
  case unsupportedSchemaVersion(Int?)
  /// A required top-level or per-turn key was missing.
  case missingRequiredField(String)
  /// A field had the wrong type for its declared contract.
  case invalidFieldType(field: String, expected: String)
  /// A turn's `agent` value is not declared in the scenario's personas.
  case unknownAgent(String)
  /// A turn's `phase_type` is not a recognised ``PhaseType`` raw value.
  case unknownPhaseType(String)
}

/// Primitive ``ReplaySource`` that reads a demo-replay YAML document
/// (`docs/specs/demo-replay-spec.md` §3.2) and yields the recorded
/// ``SimulationEvent`` sequence back out via ``events()``.
///
/// Shipped as part of the Phase 2 E1 "YAML simulation replay primitive"
/// (Issue #167). The DL-time `BundledDemoReplaySource` (#C) and future
/// `UserSimulationReplaySource` (Phase 2.5+, spec §4.5) compose on top
/// of this type.
///
/// **Actor isolation.** Declared `nonisolated` at the type level: the
/// project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would
/// otherwise infer MainActor for the `AsyncStream` closure body in
/// ``events()`` and break `Sendable` conformance on ``ReplaySource``.
/// See `.claude/rules/llm.md` and the same pattern at
/// ``LLMService/generateStream(system:user:)``.
///
/// **Scenario resolution is caller's concern.** This type accepts a
/// pre-resolved ``Scenario`` in its initialiser. Resolving a
/// `preset_ref.id` to a shipped preset and verifying the SHA-256 drift
/// guard (spec §3.3) is `BundledDemoReplaySource`'s job — not this
/// primitive's — because the rule set differs between bundled demos
/// (strict preset-only resolution) and future user-replay (arbitrary
/// saved scenarios).
nonisolated public final class YAMLReplaySource: ReplaySource {

  // MARK: - Compiled plan

  /// Classifies a planned event so the emitter can pick the right
  /// pre-yield delay from ``ReplayPlaybackConfig`` — pacing is a
  /// consumer-side decision, not persisted per-event.
  private enum EventKind: Sendable { case turn, codePhase }

  private struct PlannedEvent: Sendable {
    let kind: EventKind
    let event: SimulationEvent
  }

  /// Chronological-merge entry used only during init to build
  /// ``pacedPlan``. Carries the `(round, phase_index, phase_type)`
  /// coordinates plus a stable secondary sort key so `turns` /
  /// `code_phase_events` can be merged while preserving within-section
  /// source order.
  private struct ChronologicalEntry: Sendable {
    let round: Int
    let phaseIndex: Int
    let phaseType: PhaseType
    let sourceOrder: Int
    let paceKind: PacedEvent.Kind
    let event: SimulationEvent
  }

  // MARK: - Stored state

  private let scenarioValue: Scenario
  private let plan: [PlannedEvent]
  /// Chronologically-sorted ``PacedEvent`` array with synthesised
  /// `.roundStarted` / `.phaseStarted` lifecycle events. Computed once
  /// at init and returned verbatim by ``plannedEvents()``; stability
  /// across calls is structural (`let`), which
  /// ``ReplaySource/plannedEvents()``'s contract depends on for
  /// resume-from-position.
  private let pacedPlan: [PacedEvent]
  private let config: ReplayPlaybackConfig

  public var scenario: Scenario { scenarioValue }

  // MARK: - Init

  /// Parses `yaml` and pre-computes the event plan.
  ///
  /// The plan is built once at init so ``events()`` can be called
  /// multiple times without re-parsing (required for the loop
  /// behaviour in spec §4.9).
  public convenience init(
    yaml: String, scenario: Scenario,
    config: ReplayPlaybackConfig = .demoDefault
  ) throws {
    try self.init(yamlData: Data(yaml.utf8), scenario: scenario, config: config)
  }

  public init(
    yamlData: Data, scenario: Scenario,
    config: ReplayPlaybackConfig = .demoDefault
  ) throws {
    guard
      let parsed = try Self.loadYAML(yamlData),
      let root = parsed as? [String: Any]
    else {
      throw YAMLReplaySourceError.malformedYAML(
        description: "Top-level is not a mapping.")
    }
    let schemaValue = root["schema_version"] as? Int
    guard schemaValue == YAMLReplayExporter.schemaVersion else {
      throw YAMLReplaySourceError.unsupportedSchemaVersion(schemaValue)
    }

    let personas = Set(scenario.personas.map(\.name))
    var plan: [PlannedEvent] = []
    var chronological: [ChronologicalEntry] = []

    let turns = (root["turns"] as? [[String: Any]]) ?? []
    for (idx, raw) in turns.enumerated() {
      let parsed = try Self.parseTurn(raw, allowedAgents: personas)
      plan.append(PlannedEvent(kind: .turn, event: parsed.event))
      chronological.append(
        ChronologicalEntry(
          round: parsed.round, phaseIndex: parsed.phaseIndex,
          phaseType: parsed.phaseType, sourceOrder: idx,
          paceKind: .turn, event: parsed.event))
    }

    let codeEvents = (root["code_phase_events"] as? [[String: Any]]) ?? []
    for (idx, raw) in codeEvents.enumerated() {
      let parsed = try Self.parseCodePhaseEvent(raw)
      plan.append(PlannedEvent(kind: .codePhase, event: parsed.event))
      chronological.append(
        ChronologicalEntry(
          round: parsed.round, phaseIndex: parsed.phaseIndex,
          phaseType: parsed.phaseType,
          // `+ turns.count` keeps turn source-order strictly below
          // code-event source-order for a stable tie-break when two
          // entries land at the same (round, phase_index).
          sourceOrder: idx + turns.count,
          paceKind: .codePhase, event: parsed.event))
    }

    self.scenarioValue = scenario
    self.plan = plan
    self.pacedPlan = Self.buildPacedPlan(
      entries: chronological, totalRounds: scenario.rounds)
    self.config = config
  }

  // MARK: - ReplaySource

  public func events() -> AsyncStream<SimulationEvent> {
    let plan = self.plan
    let turnDelay = config.turnDelayMs
    let codePhaseDelay = config.codePhaseDelayMs
    let speed = max(config.speedMultiplier, 0.001)
    return AsyncStream { continuation in
      let task = Task {
        for planned in plan {
          if Task.isCancelled { break }
          let baseDelay = planned.kind == .turn ? turnDelay : codePhaseDelay
          let sleepMs = Int(Double(baseDelay) / speed)
          if sleepMs > 0 {
            try? await Task.sleep(for: .milliseconds(sleepMs))
          }
          if Task.isCancelled { break }
          continuation.yield(planned.event)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func plannedEvents() -> [PacedEvent] { pacedPlan }

  // MARK: - Paced plan construction

  /// Merges turn + code-phase entries chronologically by
  /// `(round, phase_index, sourceOrder)` and inserts synthesised
  /// `.roundStarted` / `.phaseStarted` lifecycle markers ahead of the
  /// first event of each new round / phase boundary.
  ///
  /// Explicitly NOT synthesised (see ``ReplaySource/plannedEvents()``
  /// doc for rationale): `.roundCompleted`, `.simulationCompleted`.
  private static func buildPacedPlan(
    entries: [ChronologicalEntry], totalRounds: Int
  ) -> [PacedEvent] {
    let sorted = entries.sorted { lhs, rhs in
      if lhs.round != rhs.round { return lhs.round < rhs.round }
      if lhs.phaseIndex != rhs.phaseIndex { return lhs.phaseIndex < rhs.phaseIndex }
      return lhs.sourceOrder < rhs.sourceOrder
    }
    var result: [PacedEvent] = []
    var lastRound: Int?
    var lastPhaseIndex: Int?
    var lastPhaseType: PhaseType?
    for entry in sorted {
      if lastRound != entry.round {
        result.append(
          PacedEvent(
            kind: .lifecycle,
            event: .roundStarted(round: entry.round, totalRounds: totalRounds)))
        lastRound = entry.round
        // Force a phaseStarted synthesis on round transition even if the
        // phase coordinates happen to match the previous round's last
        // phase — semantically a new round's first phase starts fresh.
        lastPhaseIndex = nil
        lastPhaseType = nil
      }
      if lastPhaseIndex != entry.phaseIndex || lastPhaseType != entry.phaseType {
        result.append(
          PacedEvent(
            kind: .lifecycle,
            // `phasePath: [phaseIndex]` is flattened per the known
            // fidelity gap documented in ``ReplaySource/plannedEvents()``
            // (matches ``YAMLReplayExporter.resolvePhaseIndices`` scope).
            event: .phaseStarted(phaseType: entry.phaseType, phasePath: [entry.phaseIndex])))
        lastPhaseIndex = entry.phaseIndex
        lastPhaseType = entry.phaseType
      }
      result.append(PacedEvent(kind: entry.paceKind, event: entry.event))
    }
    return result
  }
}

// MARK: - YAML parsing helpers
//
// Moved into an extension so `type_body_length` counts only the primary
// class body — the decode helpers are glue around Yams' `[String: Any]`
// shape and don't belong on the main class's conceptual surface.

extension YAMLReplaySource {

  // MARK: YAML loading

  private static func loadYAML(_ data: Data) throws -> Any? {
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAMLReplaySourceError.malformedYAML(
        description: "Input is not valid UTF-8.")
    }
    do {
      return try Yams.load(yaml: text)
    } catch {
      throw YAMLReplaySourceError.malformedYAML(
        description: error.localizedDescription)
    }
  }

  // MARK: - Planning: turns

  /// Parsed turn carrying the chronological coordinates needed to
  /// build ``pacedPlan`` alongside the existing ``PlannedEvent``.
  private struct ParsedTurn: Sendable {
    let round: Int
    let phaseIndex: Int
    let phaseType: PhaseType
    let event: SimulationEvent
  }

  /// Parsed code-phase event with the same coordinate shape as
  /// ``ParsedTurn``.
  private struct ParsedCodeEvent: Sendable {
    let round: Int
    let phaseIndex: Int
    let phaseType: PhaseType
    let event: SimulationEvent
  }

  private static func parseTurn(
    _ raw: [String: Any], allowedAgents: Set<String>
  ) throws -> ParsedTurn {
    guard let phaseTypeRaw = raw["phase_type"] as? String else {
      throw YAMLReplaySourceError.missingRequiredField("phase_type")
    }
    guard let phaseType = PhaseType(rawValue: phaseTypeRaw) else {
      throw YAMLReplaySourceError.unknownPhaseType(phaseTypeRaw)
    }
    guard let agent = raw["agent"] as? String else {
      throw YAMLReplaySourceError.missingRequiredField("agent")
    }
    guard allowedAgents.contains(agent) else {
      throw YAMLReplaySourceError.unknownAgent(agent)
    }
    let fields = try Self.decodeStringMap(raw["fields"], field: "fields")
    // `round` / `phase_index` default to 0 if absent so a malformed or
    // older-schema YAML still parses — the drift guard and consistency
    // check live at the CI level (spec §3.3), not at load time.
    let round = (raw["round"] as? Int) ?? 0
    let phaseIndex = (raw["phase_index"] as? Int) ?? 0
    return ParsedTurn(
      round: round,
      phaseIndex: phaseIndex,
      phaseType: phaseType,
      event: .agentOutput(
        agent: agent, output: TurnOutput(fields: fields),
        phaseType: phaseType))
  }

  /// Decodes a `[String: String]` mapping from a YAML value produced by
  /// Yams. Yams returns `[String: Any]` or `[AnyHashable: Any]` for
  /// mappings depending on key types; handle both plus an empty-flow
  /// form.
  private static func decodeStringMap(
    _ value: Any?, field: String
  ) throws -> [String: String] {
    guard let value else { return [:] }
    if let map = value as? [String: Any] {
      return map.compactMapValues { any in
        if let str = any as? String { return str }
        return String(describing: any)
      }
    }
    if let map = value as? [AnyHashable: Any] {
      var result: [String: String] = [:]
      for (rawKey, rawValue) in map {
        guard let key = rawKey as? String else {
          throw YAMLReplaySourceError.invalidFieldType(
            field: field, expected: "string-keyed mapping")
        }
        if let str = rawValue as? String {
          result[key] = str
        } else {
          result[key] = String(describing: rawValue)
        }
      }
      return result
    }
    throw YAMLReplaySourceError.invalidFieldType(
      field: field, expected: "mapping")
  }

  // MARK: - Planning: code_phase_events

  private static func parseCodePhaseEvent(
    _ raw: [String: Any]
  ) throws -> ParsedCodeEvent {
    let summary = (raw["summary"] as? String) ?? ""
    let round = (raw["round"] as? Int) ?? 0
    let phaseIndex = (raw["phase_index"] as? Int) ?? 0
    // `phase_type` is denormalised on code-phase entries in the YAML
    // (spec §3.2). Unknown values are treated as planning-level drift
    // and rejected via ``unknownPhaseType`` — symmetric with turns.
    let phaseType: PhaseType
    if let raw = raw["phase_type"] as? String {
      guard let parsed = PhaseType(rawValue: raw) else {
        throw YAMLReplaySourceError.unknownPhaseType(raw)
      }
      phaseType = parsed
    } else {
      // Missing `phase_type` on code events is tolerated (older writers
      // may have omitted it). Default to `.scoreCalc` so the lifecycle
      // synthesis has a stable label; consumers that rely on the exact
      // type for rendering will re-derive from `phasePath` against the
      // scenario if needed.
      phaseType = .scoreCalc
    }
    let event: SimulationEvent
    if let payload = raw["payload"] as? [String: Any],
      let decoded = try decodePayloadStanza(payload, summary: summary) {
      event = decoded
    } else {
      // Fallback: no structured payload — surface as a narrative summary.
      event = .summary(text: summary)
    }
    return ParsedCodeEvent(
      round: round, phaseIndex: phaseIndex, phaseType: phaseType, event: event)
  }

  /// Decodes a `payload:` stanza as emitted by ``YAMLReplayExporter``.
  /// Returns `nil` when the `kind` discriminator is absent or unknown
  /// — callers fall back to `.summary(text:)` so the replay keeps
  /// playing instead of stalling on unfamiliar data.
  private static func decodePayloadStanza(
    _ payload: [String: Any], summary: String
  ) throws -> SimulationEvent? {
    guard let kind = payload["kind"] as? String else { return nil }
    switch kind {
    case "elimination": return try decodeElimination(payload)
    case "scoreUpdate": return try decodeScoreUpdate(payload)
    case "summary": return .summary(text: summary)
    case "voteResults": return try decodeVoteResults(payload)
    case "pairingResult": return try decodePairingResult(payload)
    case "assignment": return try decodeAssignment(payload)
    case "eventInjected": return decodeEventInjected(payload)
    default: return nil
    }
  }

  private static func decodeElimination(
    _ payload: [String: Any]
  ) throws -> SimulationEvent {
    guard let agent = payload["agent"] as? String else {
      throw YAMLReplaySourceError.missingRequiredField("payload.agent")
    }
    let voteCount = payload["vote_count"] as? Int ?? 0
    return .elimination(agent: agent, voteCount: voteCount)
  }

  private static func decodeScoreUpdate(
    _ payload: [String: Any]
  ) throws -> SimulationEvent {
    let scores = try decodeIntMap(payload["scores"], field: "payload.scores")
    return .scoreUpdate(scores: scores)
  }

  private static func decodeVoteResults(
    _ payload: [String: Any]
  ) throws -> SimulationEvent {
    let votes = try decodeStringMap(payload["votes"], field: "payload.votes")
    let tallies = try decodeIntMap(payload["tallies"], field: "payload.tallies")
    return .voteResults(votes: votes, tallies: tallies)
  }

  private static func decodePairingResult(
    _ payload: [String: Any]
  ) throws -> SimulationEvent {
    guard let agent1 = payload["agent1"] as? String else {
      throw YAMLReplaySourceError.missingRequiredField("payload.agent1")
    }
    guard let agent2 = payload["agent2"] as? String else {
      throw YAMLReplaySourceError.missingRequiredField("payload.agent2")
    }
    let action1 = payload["action1"] as? String ?? ""
    let action2 = payload["action2"] as? String ?? ""
    return .pairingResult(
      agent1: agent1, action1: action1, agent2: agent2, action2: action2)
  }

  private static func decodeAssignment(
    _ payload: [String: Any]
  ) throws -> SimulationEvent {
    guard let agent = payload["agent"] as? String else {
      throw YAMLReplaySourceError.missingRequiredField("payload.agent")
    }
    let value = payload["value"] as? String ?? ""
    return .assignment(agent: agent, value: value)
  }

  /// Decodes an `event_inject` payload. The miss case (`event: null`)
  /// is meaningful — exporter writes it explicitly so the timeline can
  /// distinguish "phase didn't run" from "rolled and lost". `event`
  /// absent (legacy / hand-written replays) also maps to nil.
  private static func decodeEventInjected(
    _ payload: [String: Any]
  ) -> SimulationEvent {
    let event = payload["event"] as? String
    return .eventInjected(event: event)
  }

  private static func decodeIntMap(
    _ value: Any?, field: String
  ) throws -> [String: Int] {
    guard let value else { return [:] }
    if let map = value as? [String: Any] {
      return map.compactMapValues { $0 as? Int }
    }
    if let map = value as? [AnyHashable: Any] {
      var result: [String: Int] = [:]
      for (rawKey, rawValue) in map {
        guard let key = rawKey as? String else {
          throw YAMLReplaySourceError.invalidFieldType(
            field: field, expected: "string-keyed integer mapping")
        }
        if let intValue = rawValue as? Int { result[key] = intValue }
      }
      return result
    }
    throw YAMLReplaySourceError.invalidFieldType(
      field: field, expected: "mapping")
  }
}
