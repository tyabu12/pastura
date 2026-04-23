import Foundation
import Yams

/// Parses YAML scenario definitions into ``Scenario`` models.
///
/// Uses `Yams.load(yaml:)` → `[String: Any]` with manual mapping per ADR-001.
/// Strips code fences from LLM-generated YAML before parsing.
nonisolated struct ScenarioLoader: Sendable {  // swiftlint:disable:this type_body_length

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

  /// Extracts a required field of exact Swift type `T` from a YAML dictionary.
  ///
  /// Distinguishes *missing* from *present-but-wrong-type* so users can tell
  /// whether to add the field or re-type it. Wrong-type errors name the actual
  /// bridged Swift type from Yams (e.g. `"String"` for quoted numbers), so a
  /// user writing `agents: "2"` gets `"field 'agents' must be Int, got String"`
  /// instead of a misleading `"Missing required field"`.
  ///
  /// No type coercion — eliminating silent-coerce is the whole point of #130.
  private func parseRequired<T>(
    _ dict: [String: Any], key: String, label: String
  ) throws -> T {
    guard let raw = dict[key] else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): missing required field '\(key)'"
      )
    }
    guard let typed = raw as? T else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): field '\(key)' must be \(T.self), got \(type(of: raw))"
      )
    }
    return typed
  }

  /// Extracts an optional field of exact Swift type `T` from a YAML dictionary.
  ///
  /// Returns `nil` when the key is absent. Throws when present-but-wrong-type —
  /// unlike a naive `as? T` which would silently coerce to `nil` and let the
  /// caller's default kick in (the bug class tracked in #130).
  private func parseOptional<T>(
    _ dict: [String: Any], key: String, label: String
  ) throws -> T? {
    guard let raw = dict[key] else { return nil }
    guard let typed = raw as? T else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): field '\(key)' must be \(T.self), got \(type(of: raw))"
      )
    }
    return typed
  }

  /// Maps a raw YAML dictionary to a ``Scenario`` model.
  private func mapToScenario(_ dict: [String: Any]) throws -> Scenario {
    let id: String = try parseRequired(dict, key: "id", label: "Scenario")
    let name: String = try parseRequired(dict, key: "name", label: "Scenario")
    let description: String = try parseRequired(dict, key: "description", label: "Scenario")
    let agentCount: Int = try parseRequired(dict, key: "agents", label: "Scenario")
    let rounds: Int = try parseRequired(dict, key: "rounds", label: "Scenario")
    let context: String = try parseRequired(dict, key: "context", label: "Scenario")

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

    let extraData = try collectExtraData(from: dict)

    return Scenario(
      id: id, name: name, description: description,
      agentCount: agentCount, rounds: rounds, context: context,
      personas: personas, phases: phases, extraData: extraData
    )
  }

  /// Collects non-standard top-level keys as extra data. Throws on unsupported
  /// shapes rather than silently dropping them — previously, a typo like
  /// `count: 42` (auto-typed Int) disappeared from the returned map.
  private func collectExtraData(
    from dict: [String: Any]
  ) throws -> [String: AnyCodableValue] {
    var extraData: [String: AnyCodableValue] = [:]
    for (key, value) in dict where !Self.standardKeys.contains(key) {
      extraData[key] = try convertToAnyCodableValue(value, key: key)
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

    let prompt: String? = try parseOptional(dict, key: "prompt", label: label)
    let template: String? = try parseOptional(dict, key: "template", label: label)
    let source: String? = try parseOptional(dict, key: "source", label: label)
    let excludeSelf: Bool? = try parseOptional(dict, key: "exclude_self", label: label)
    let options: [String]? = try parseOptional(dict, key: "options", label: label)

    let target = try parseAssignTarget(dict["target"], label: label)
    let outputSchema = try parseOutputSchema(dict, label: label)
    let pairing = try parsePairing(dict["pairing"], label: label)
    let logic = try parseLogic(dict["logic"], label: label)

    // speak_each rounds → subRounds
    let subRounds: Int? = try parseOptional(dict, key: "rounds", label: label)

    // Conditional-specific fields (`if:` expression + `then:` / `else:` sub-phase arrays).
    // Recursively descend with depth+1 so nested conditional is rejected here.
    let condition: String? = try parseOptional(dict, key: "if", label: label)
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

  /// Parses the `output:` schema dict. Values must be Strings — the schema is
  /// an LLM prompt hint, and a non-String value (e.g. `count: 1`) is a typo,
  /// not a type-shorthand worth preserving. Previously stringified silently.
  private func parseOutputSchema(
    _ dict: [String: Any], label: String
  ) throws -> [String: String]? {
    guard let raw = dict["output"] else { return nil }
    guard let output = raw as? [String: Any] else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): field 'output' must be a dictionary of String values, got \(type(of: raw))"
      )
    }
    var result: [String: String] = [:]
    for (key, value) in output {
      guard let str = value as? String else {
        throw SimulationError.scenarioValidationFailed(
          "\(label): output schema value for '\(key)' must be String, got \(type(of: value))"
        )
      }
      result[key] = str
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

  /// Converts a raw YAML value to ``AnyCodableValue``, throwing on unsupported
  /// shapes rather than silently dropping the field or coercing to a surprising
  /// string. `AnyCodableValue` is String-leaf today; extending it to carry
  /// Int/Bool/Double is deferred to a future issue. Users wanting a numeric
  /// scalar at the top level should quote it (`count: "42"`).
  private static let supportedExtraDataShapes =
    "String, [String], [String: String], or [[String: String]]"

  private func convertToAnyCodableValue(
    _ value: Any, key: String
  ) throws -> AnyCodableValue {
    if let str = value as? String {
      return .string(str)
    }
    if let arr = value as? [Any] {
      if let dictArr = arr as? [[String: String]] {
        return .arrayOfDictionaries(dictArr)
      }
      // Array of dicts where any value isn't a String — previously stringified
      // silently, which hid typos like `majority: 1`.
      if arr.allSatisfy({ $0 is [String: Any] }) {
        throw SimulationError.scenarioValidationFailed(
          "Top-level field '\(key)': array-of-dict values must all be String. "
            + "Quote non-string values (e.g. `majority: \"1\"`)."
        )
      }
      if arr.allSatisfy({ $0 is String }) {
        // Unreachable when the pure-String cast above succeeded; kept for
        // clarity against future changes to Swift's Array<Any> bridging.
        return .array(arr.compactMap { $0 as? String })
      }
      throw SimulationError.scenarioValidationFailed(
        "Top-level field '\(key)': mixed-type arrays are not supported. "
          + "Use a pure [String] or [[String: String]]."
      )
    }
    if let dict = value as? [String: String] {
      return .dictionary(dict)
    }
    if value is [String: Any] {
      throw SimulationError.scenarioValidationFailed(
        "Top-level field '\(key)': dictionary values must all be String. "
          + "Quote non-string values."
      )
    }
    throw SimulationError.scenarioValidationFailed(
      "Top-level field '\(key)' has unsupported type \(type(of: value)). "
        + "Supported shapes: \(Self.supportedExtraDataShapes)."
    )
  }
}
