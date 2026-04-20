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

  /// One replay event with its associated pre-emit sleep.
  private struct PlannedEvent: Sendable {
    let delayMs: Int
    let event: SimulationEvent
  }

  // MARK: - Stored state

  private let scenarioValue: Scenario
  private let plan: [PlannedEvent]
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

    let turns = (root["turns"] as? [[String: Any]]) ?? []
    for raw in turns {
      plan.append(try Self.planTurn(raw, allowedAgents: personas))
    }

    let codeEvents = (root["code_phase_events"] as? [[String: Any]]) ?? []
    for raw in codeEvents {
      plan.append(try Self.planCodePhaseEvent(raw))
    }

    self.scenarioValue = scenario
    self.plan = plan
    self.config = config
  }

  // MARK: - ReplaySource

  public func events() -> AsyncStream<SimulationEvent> {
    let plan = self.plan
    let speed = max(config.speedMultiplier, 0.001)
    return AsyncStream { continuation in
      let task = Task {
        for planned in plan {
          if Task.isCancelled { break }
          let sleepMs = Int(Double(planned.delayMs) / speed)
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

  // MARK: - YAML loading

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

  private static func planTurn(
    _ raw: [String: Any], allowedAgents: Set<String>
  ) throws -> PlannedEvent {
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
    let delay = raw["delay_ms_before"] as? Int ?? YAMLReplayExporter.defaultTurnDelayMs
    return PlannedEvent(
      delayMs: delay,
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
      for (k, v) in map {
        guard let key = k as? String else {
          throw YAMLReplaySourceError.invalidFieldType(
            field: field, expected: "string-keyed mapping")
        }
        if let str = v as? String {
          result[key] = str
        } else {
          result[key] = String(describing: v)
        }
      }
      return result
    }
    throw YAMLReplaySourceError.invalidFieldType(
      field: field, expected: "mapping")
  }

  // MARK: - Planning: code_phase_events

  private static func planCodePhaseEvent(
    _ raw: [String: Any]
  ) throws -> PlannedEvent {
    let summary = (raw["summary"] as? String) ?? ""
    let delay = raw["delay_ms_before"] as? Int ?? YAMLReplayExporter.defaultCodePhaseDelayMs
    if let payload = raw["payload"] as? [String: Any],
      let event = try decodePayloadStanza(payload, summary: summary) {
      return PlannedEvent(delayMs: delay, event: event)
    }
    // Fallback: no structured payload — surface as a narrative summary.
    return PlannedEvent(delayMs: delay, event: .summary(text: summary))
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
    case "elimination":
      guard let agent = payload["agent"] as? String else {
        throw YAMLReplaySourceError.missingRequiredField("payload.agent")
      }
      let voteCount = payload["vote_count"] as? Int ?? 0
      return .elimination(agent: agent, voteCount: voteCount)
    case "scoreUpdate":
      let scores = try decodeIntMap(payload["scores"], field: "payload.scores")
      return .scoreUpdate(scores: scores)
    case "summary":
      return .summary(text: summary)
    case "voteResults":
      let votes = try decodeStringMap(payload["votes"], field: "payload.votes")
      let tallies = try decodeIntMap(payload["tallies"], field: "payload.tallies")
      return .voteResults(votes: votes, tallies: tallies)
    case "pairingResult":
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
    case "assignment":
      guard let agent = payload["agent"] as? String else {
        throw YAMLReplaySourceError.missingRequiredField("payload.agent")
      }
      let value = payload["value"] as? String ?? ""
      return .assignment(agent: agent, value: value)
    default:
      return nil
    }
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
      for (k, v) in map {
        guard let key = k as? String else {
          throw YAMLReplaySourceError.invalidFieldType(
            field: field, expected: "string-keyed integer mapping")
        }
        if let i = v as? Int { result[key] = i }
      }
      return result
    }
    throw YAMLReplaySourceError.invalidFieldType(
      field: field, expected: "mapping")
  }
}
