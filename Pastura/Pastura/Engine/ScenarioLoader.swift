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
  /// - Code phases: 0
  static func estimateInferenceCount(_ scenario: Scenario) -> Int {
    let agents = scenario.agentCount
    var perRound = 0

    for phase in scenario.phases {
      switch phase.type {
      case .speakAll:
        perRound += agents
      case .speakEach:
        perRound += agents * (phase.subRounds ?? 1)
      case .vote:
        perRound += agents
      case .choose:
        if phase.pairing == .roundRobin {
          perRound += agents * 2
        } else {
          perRound += agents
        }
      case .scoreCalc, .assign, .eliminate, .summarize:
        break
      }
    }

    return perRound * scenario.rounds
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

  private func mapPhase(_ dict: [String: Any], index: Int) throws -> Phase {
    guard let typeString = dict["type"] as? String else {
      throw SimulationError.scenarioValidationFailed("Phase \(index) missing 'type'")
    }
    guard let phaseType = PhaseType(rawValue: typeString) else {
      throw SimulationError.scenarioValidationFailed(
        "Phase \(index) has invalid type: '\(typeString)'"
      )
    }

    let prompt = dict["prompt"] as? String
    let template = dict["template"] as? String
    let source = dict["source"] as? String
    let target = dict["target"] as? String
    let excludeSelf = dict["exclude_self"] as? Bool
    let options = dict["options"] as? [String]

    // output → outputSchema
    var outputSchema: [String: String]?
    if let output = dict["output"] as? [String: Any] {
      outputSchema = [:]
      for (key, value) in output {
        outputSchema?[key] = "\(value)"
      }
    }

    // pairing
    var pairing: PairingStrategy?
    if let pairingStr = dict["pairing"] as? String {
      pairing = PairingStrategy(rawValue: pairingStr)
    }

    // logic
    var logic: ScoreCalcLogic?
    if let logicStr = dict["logic"] as? String {
      logic = ScoreCalcLogic(rawValue: logicStr)
    }

    // speak_each rounds → subRounds
    let subRounds = dict["rounds"] as? Int

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
      subRounds: subRounds
    )
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
