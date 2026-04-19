import Foundation
import Yams

/// Parses YAML scenario definitions into ``Scenario`` models.
///
/// Uses `Yams.load(yaml:)` → `[String: Any]` with manual mapping per ADR-001.
/// Strips code fences from LLM-generated YAML before parsing.
nonisolated struct ScenarioLoader: Sendable {

  /// Standard fields that are mapped to `Scenario` properties (not collected as extraData).
  private static let standardKeys: Set<String> = [
    "id", "name", "description", "agents", "rounds", "context", "personas", "phases"
  ]

  // MARK: - Loading

  /// Parse a YAML string into a ``Scenario`` model.
  ///
  /// - Parameter yaml: Raw YAML text, possibly wrapped in code fences.
  /// - Returns: A validated ``Scenario`` instance.
  /// - Throws: ``SimulationError/scenarioValidationFailed(_:)`` on parse or validation failure.
  func load(yaml: String) throws -> Scenario {
    let stripped = stripCodeFences(yaml)

    guard let raw = try? Yams.load(yaml: stripped),
      let dict = raw as? [String: Any]
    else {
      throw SimulationError.scenarioValidationFailed("Invalid YAML format")
    }

    return try mapToScenario(dict)
  }

  // MARK: - Inference Estimation

  /// Estimates the total number of LLM inferences for a scenario.
  ///
  /// Formula per round:
  /// - `speak_all`: agentCount
  /// - `speak_each`: agentCount × subRounds
  /// - `vote`: agentCount
  /// - `choose`: agentCount × 2 (round_robin) or agentCount (individual)
  /// - `conditional`: `max(sum(thenPhases), sum(elsePhases))` — only one branch
  ///   runs per invocation, so `max` matches execution semantics. Using `sum`
  ///   would artificially block scenarios designed with asymmetric branches
  ///   (e.g. an expensive reflect phase gated behind a rare condition).
  /// - Code phases: 0
  static func estimateInferenceCount(_ scenario: Scenario) -> Int {
    let agents = scenario.agentCount
    let perRound = scenario.phases.reduce(0) { $0 + estimatePhase($1, agents: agents) }
    return perRound * scenario.rounds
  }

  /// Per-phase estimate used by both top-level and conditional-branch recursion.
  private static func estimatePhase(_ phase: Phase, agents: Int) -> Int {
    switch phase.type {
    case .speakAll:
      return agents
    case .speakEach:
      return agents * (phase.subRounds ?? 1)
    case .vote:
      return agents
    case .choose:
      return phase.pairing == .roundRobin ? agents * 2 : agents
    case .scoreCalc, .assign, .eliminate, .summarize:
      return 0
    case .conditional:
      let thenCost = (phase.thenPhases ?? []).reduce(0) { $0 + estimatePhase($1, agents: agents) }
      let elseCost = (phase.elsePhases ?? []).reduce(0) { $0 + estimatePhase($1, agents: agents) }
      return max(thenCost, elseCost)
    }
  }

  // MARK: - Private

  /// Removes markdown code fences that LLMs sometimes wrap around YAML.
  private func stripCodeFences(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    let filtered = lines.filter { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      return !trimmed.hasPrefix("```")
    }
    return filtered.joined(separator: "\n")
  }

  /// Extracts a required string field from a YAML dictionary.
  private func requireString(_ dict: [String: Any], key: String) throws -> String {
    if let value = dict[key] as? String { return value }
    if let value = dict[key] { return "\(value)" }
    throw SimulationError.scenarioValidationFailed("Missing required field: \(key)")
  }

  /// Extracts a required integer field from a YAML dictionary.
  private func requireInt(_ dict: [String: Any], key: String) throws -> Int {
    guard let value = dict[key] as? Int else {
      throw SimulationError.scenarioValidationFailed("Missing required field: \(key)")
    }
    return value
  }

  /// Maps a raw YAML dictionary to a ``Scenario`` model.
  private func mapToScenario(_ dict: [String: Any]) throws -> Scenario {
    let id = try requireString(dict, key: "id")
    let name = try requireString(dict, key: "name")
    let description = try requireString(dict, key: "description")
    let agentCount = try requireInt(dict, key: "agents")
    let rounds = try requireInt(dict, key: "rounds")
    let context = try requireString(dict, key: "context")

    guard let personasRaw = dict["personas"] as? [[String: Any]] else {
      throw SimulationError.scenarioValidationFailed("Missing or invalid field: personas")
    }
    guard let phasesRaw = dict["phases"] as? [[String: Any]] else {
      throw SimulationError.scenarioValidationFailed("Missing or invalid field: phases")
    }

    let personas = try personasRaw.map { try mapPersona($0) }
    if personas.count != agentCount {
      throw SimulationError.scenarioValidationFailed(
        "agents (\(agentCount)) does not match personas count (\(personas.count))"
      )
    }

    let phases = try phasesRaw.enumerated().map { index, raw in
      try mapPhase(raw, index: index)
    }

    let extraData = collectExtraData(from: dict)

    return Scenario(
      id: id, name: name, description: description,
      agentCount: agentCount, rounds: rounds, context: context,
      personas: personas, phases: phases, extraData: extraData
    )
  }

  /// Collects non-standard top-level keys as extra data.
  private func collectExtraData(from dict: [String: Any]) -> [String: AnyCodableValue] {
    var extraData: [String: AnyCodableValue] = [:]
    for (key, value) in dict where !Self.standardKeys.contains(key) {
      if let converted = convertToAnyCodableValue(value) {
        extraData[key] = converted
      }
    }
    return extraData
  }

  private func mapPersona(_ dict: [String: Any]) throws -> Persona {
    guard let name = dict["name"] as? String else {
      throw SimulationError.scenarioValidationFailed("Persona missing 'name'")
    }
    let description = dict["description"] as? String ?? ""
    return Persona(name: name, description: description)
  }

  /// Strict-throw on unknown, mirroring PhaseType. See issue #108.
  private func parseAssignTarget(_ raw: Any?, label: String) throws -> AssignTarget? {
    guard let targetStr = raw as? String else { return nil }
    guard let parsed = AssignTarget(rawValue: targetStr) else {
      throw SimulationError.scenarioValidationFailed(
        "\(label) has invalid target: '\(targetStr)'. Use 'all' or 'random_one'."
      )
    }
    return parsed
  }

  private func parsePairing(_ raw: Any?, label: String) throws -> PairingStrategy? {
    guard let str = raw as? String else { return nil }
    guard let parsed = PairingStrategy(rawValue: str) else {
      throw SimulationError.scenarioValidationFailed(
        "\(label) has invalid pairing: '\(str)'. Use 'round_robin'."
      )
    }
    return parsed
  }

  private func parseLogic(_ raw: Any?, label: String) throws -> ScoreCalcLogic? {
    guard let str = raw as? String else { return nil }
    guard let parsed = ScoreCalcLogic(rawValue: str) else {
      let allowed = ScoreCalcLogic.allCases.map(\.rawValue).joined(separator: ", ")
      throw SimulationError.scenarioValidationFailed(
        "\(label) has invalid logic: '\(str)'. Expected one of: \(allowed)."
      )
    }
    return parsed
  }

  private func mapPhase(_ dict: [String: Any], index: Int) throws -> Phase {
    try mapPhase(dict, label: "Phase \(index)", depth: 0)
  }

  /// Maps a phase dictionary, recursively descending into conditional
  /// branches. `depth == 0` is top-level; `depth >= 1` rejects nested
  /// `.conditional` to defend the depth-1 rule at parse time
  /// (the validator has the same check for non-YAML construction paths).
  ///
  /// `label` is used in error messages: top-level calls pass `"Phase K"`,
  /// nested calls pass `"Phase K.then[N]"` / `"Phase K.else[N]"` so the
  /// user can locate the offending sub-phase in their YAML.
  private func mapPhase(_ dict: [String: Any], label: String, depth: Int) throws -> Phase {
    let phaseType = try parsePhaseType(dict, label: label, depth: depth)

    let prompt = dict["prompt"] as? String
    let template = dict["template"] as? String
    let source = dict["source"] as? String
    let excludeSelf = dict["exclude_self"] as? Bool
    let options = dict["options"] as? [String]

    let target = try parseAssignTarget(dict["target"], label: label)
    let outputSchema = parseOutputSchema(dict)
    let pairing = try parsePairing(dict["pairing"], label: label)
    let logic = try parseLogic(dict["logic"], label: label)

    // speak_each rounds → subRounds
    let subRounds = dict["rounds"] as? Int

    // Conditional-specific fields (`if:` expression + `then:` / `else:` sub-phase arrays).
    // Recursively descend with depth+1 so nested conditional is rejected here.
    let condition = dict["if"] as? String
    let thenPhases = try mapBranch(
      dict["then"], branchLabel: "then", parentLabel: label, depth: depth)
    let elsePhases = try mapBranch(
      dict["else"], branchLabel: "else", parentLabel: label, depth: depth)

    return Phase(
      type: phaseType,
      prompt: prompt,
      outputSchema: outputSchema,
      options: options,
      pairing: pairing,
      logic: logic,
      template: template,
      source: source,
      target: target,
      excludeSelf: excludeSelf,
      subRounds: subRounds,
      condition: condition,
      thenPhases: thenPhases,
      elsePhases: elsePhases
    )
  }

  private func parsePhaseType(
    _ dict: [String: Any], label: String, depth: Int
  ) throws -> PhaseType {
    guard let typeString = dict["type"] as? String else {
      throw SimulationError.scenarioValidationFailed("\(label) missing 'type'")
    }
    guard let phaseType = PhaseType(rawValue: typeString) else {
      throw SimulationError.scenarioValidationFailed(
        "\(label) has invalid type: '\(typeString)'"
      )
    }
    if phaseType == .conditional && depth > 0 {
      throw SimulationError.scenarioValidationFailed(
        "\(label): nested 'conditional' inside another conditional is not "
          + "allowed (depth-1 rule)."
      )
    }
    return phaseType
  }

  private func parseOutputSchema(_ dict: [String: Any]) -> [String: String]? {
    guard let output = dict["output"] as? [String: Any] else { return nil }
    var result: [String: String] = [:]
    for (key, value) in output {
      result[key] = "\(value)"
    }
    return result
  }

  private func mapBranch(
    _ raw: Any?, branchLabel: String, parentLabel: String, depth: Int
  ) throws -> [Phase]? {
    guard let phasesRaw = raw else { return nil }
    guard let list = phasesRaw as? [[String: Any]] else {
      throw SimulationError.scenarioValidationFailed(
        "\(parentLabel): '\(branchLabel)' must be an array of phase objects"
      )
    }
    return try list.enumerated().map { subIndex, subRaw in
      try mapPhase(
        subRaw,
        label: "\(parentLabel).\(branchLabel)[\(subIndex)]",
        depth: depth + 1
      )
    }
  }

  /// Converts a raw YAML value to ``AnyCodableValue``.
  private func convertToAnyCodableValue(_ value: Any) -> AnyCodableValue? {
    if let str = value as? String {
      return .string(str)
    }
    if let arr = value as? [Any] {
      // Try array of dictionaries first
      if let dictArr = arr as? [[String: String]] {
        return .arrayOfDictionaries(dictArr)
      }
      // Try array of [String: Any] and convert values to String
      if let dictAnyArr = arr as? [[String: Any]] {
        let converted = dictAnyArr.map { dict in
          dict.mapValues { "\($0)" } as [String: String]
        }
        return .arrayOfDictionaries(converted)
      }
      // Try string array
      let strings = arr.compactMap { $0 as? String }
      if strings.count == arr.count {
        return .array(strings)
      }
    }
    if let dict = value as? [String: String] {
      return .dictionary(dict)
    }
    return nil
  }
}
