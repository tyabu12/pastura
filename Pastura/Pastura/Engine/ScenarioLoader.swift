// Per-phase decoder dispatch + manual `[String: Any]` mapping (ADR-001)
// keeps the phase-shape switch and its helpers co-located. Splitting
// per-phase decoders into separate files would force shared mapping
// helpers to module scope and lose the locality of the dispatch table.
// swiftlint:disable file_length
import Foundation
import Yams

/// Parses YAML scenario definitions into ``Scenario`` models.
///
/// Uses `Yams.load(yaml:)` → `[String: Any]` with manual mapping per ADR-001.
/// Strips code fences from LLM-generated YAML before parsing.
///
/// Public for out-of-app consumers (the `pastura-harness` SwiftPM package,
/// ADR-013 C4) — the SPM-extraction access prep CLAUDE.md anticipates.
nonisolated public struct ScenarioLoader: Sendable {  // swiftlint:disable:this type_body_length

  /// Creates a loader. Stateless — declared explicitly because the
  /// synthesized initializer would be `internal`, invisible to the
  /// harness package (ADR-013 C4).
  public init() {}

  /// Standard fields that are mapped to `Scenario` properties (not collected as extraData).
  private static let standardKeys: Set<String> = [
    "id", "name", "description", "language", "simulation_language",
    "agents", "rounds", "context", "personas", "phases", "log_window"
  ]

  // MARK: - Loading

  /// Parse a YAML string into a ``Scenario`` model.
  ///
  /// Enforces structural mapping plus a narrow band of construct-time
  /// invariants (accepted-`language` / `simulation_language` membership,
  /// `personas` count matching `agents`, depth-1 `conditional`). It does
  /// **not** run ``ScenarioValidator``'s execution-limit / inference-cap /
  /// phase-semantic gate — so the returned scenario is well-formed but not
  /// yet known to be runnable.
  ///
  /// Boundary contract for callers:
  /// - **Persisting** a newly-authored / ingested scenario to the database →
  ///   call ``ScenarioValidator/validateForCommit(_:)`` first (it adds the
  ///   canonical-primary-field check on top of `validate`).
  /// - **Running** a scenario → ``ScenarioValidator/validate(_:)`` (already
  ///   enforced at the run-gate in `SimulationRunner`).
  /// - **Re-parsing** already-persisted YAML (replay / export / display) →
  ///   no validation needed; the gate already ran upstream at create-time.
  ///   This exemption is the reason `load` itself stays un-validating.
  ///
  /// - Parameter yaml: Raw YAML text, possibly wrapped in code fences.
  /// - Returns: A structurally-mapped ``Scenario`` instance (not run-validated).
  /// - Throws: ``SimulationError/scenarioValidationFailed(_:)`` on a YAML
  ///   parse error or a construct-time invariant violation (wrong field type,
  ///   unknown `language`, persona/agent mismatch, malformed phase shape).
  public func load(yaml: String) throws -> Scenario {
    let stripped = stripCodeFences(yaml)

    guard let raw = try? Yams.load(yaml: stripped),
      let dict = raw as? [String: Any]
    else {
      throw validationError(String(localized: "Invalid YAML format"))
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
  /// - `reflect`: agentCount
  /// - `whisper`: (agentCount / 2) × subRounds × 2 — pair count × exchanges × speakers
  /// - `choose`: agentCount × 2 (round_robin) or agentCount (individual)
  /// - `conditional`: `max(sum(thenPhases), sum(elsePhases))` — only one branch
  ///   runs per invocation, so `max` matches execution semantics. Using `sum`
  ///   would artificially block scenarios designed with asymmetric branches
  ///   (e.g. an expensive reflect phase gated behind a rare condition).
  /// - Code phases: 0
  public static func estimateInferenceCount(_ scenario: Scenario) -> Int {
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
    case .vote, .reflect:
      return agents
    case .whisper:
      // Active agents pair off (integer division drops the odd one out) and
      // each pair runs `subRounds` exchanges of 2 utterances (both speakers).
      return (agents / 2) * (phase.subRounds ?? 1) * 2
    case .choose:
      return phase.pairing == .roundRobin ? agents * 2 : agents
    case .scoreCalc, .assign, .eliminate, .summarize, .eventInject:
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
      throw validationError(
        String(localized: "%@: missing required field '%@'"), label, key)
    }
    guard let typed = raw as? T else {
      throw validationError(
        String(localized: "%@: field '%@' must be %@, got %@"),
        label, key, String(describing: T.self), String(describing: type(of: raw)))
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
      throw validationError(
        String(localized: "%@: field '%@' must be %@, got %@"),
        label, key, String(describing: T.self), String(describing: type(of: raw)))
    }
    return typed
  }

  /// Extracts an optional `Double` field, accepting an `Int` and converting.
  ///
  /// Intentional exception to the project-wide #130 strict-no-coerce stance.
  /// The `event_inject` phase's `probability` field is the first natural-decimal
  /// `Double?` field on `Phase`; in YAML the values `0` / `1` (integers) are
  /// the most ergonomic way to write the boundary cases (always-fire /
  /// never-fire). Forcing curators to write `1.0` / `0.0` would surface the
  /// Yams Int-vs-Double bridging quirk for no curator-visible benefit.
  ///
  /// Throws on `String` / `Bool` / other types — the coercion window is
  /// strictly Int → Double, not "anything resembling a number". Bool is
  /// excluded because Swift's `as? Int` silently coerces a Bool, which would
  /// reintroduce the type-laundering bug class.
  private func parseOptionalDoubleAcceptingInt(
    _ dict: [String: Any], key: String, label: String
  ) throws -> Double? {
    guard let raw = dict[key] else { return nil }
    if let double = raw as? Double, !(raw is Bool) {
      return double
    }
    if let int = raw as? Int, !(raw is Bool) {
      return Double(int)
    }
    throw validationError(
      String(localized: "%@: field '%@' must be Double or Int, got %@"),
      label, key, String(describing: type(of: raw)))
  }

  /// Maps a raw YAML dictionary to a ``Scenario`` model.
  private func mapToScenario(_ dict: [String: Any]) throws -> Scenario {
    let id: String = try parseRequired(dict, key: "id", label: "Scenario")
    let name: String = try parseRequired(dict, key: "name", label: "Scenario")
    let description: String = try parseRequired(dict, key: "description", label: "Scenario")
    let language: String = try parseRequired(dict, key: "language", label: "Scenario")
    guard Scenario.acceptedLanguages.contains(language) else {
      let allowed = Scenario.acceptedLanguages.sorted().joined(separator: ", ")
      throw validationError(
        String(localized: "Scenario: field 'language' must be one of {%@}, got '%@'"),
        allowed, language)
    }
    let simulationLanguage: String? = try parseOptional(
      dict, key: "simulation_language", label: "Scenario")
    if let simulationLanguage, !Scenario.acceptedLanguages.contains(simulationLanguage) {
      let allowed = Scenario.acceptedLanguages.sorted().joined(separator: ", ")
      throw validationError(
        String(
          localized: "Scenario: field 'simulation_language' must be one of {%@} or absent, got '%@'"
        ),
        allowed, simulationLanguage)
    }
    let agentCount: Int = try parseRequired(dict, key: "agents", label: "Scenario")
    let rounds: Int = try parseRequired(dict, key: "rounds", label: "Scenario")
    let context: String = try parseRequired(dict, key: "context", label: "Scenario")
    // Optional prompt-side conversation-log cap (#907). Strict-Int parse
    // (mirrors `agents`/`rounds`): a quoted number or other type errors rather
    // than silently coercing. The `≥ 1` bound is enforced by ScenarioValidator.
    let logWindow: Int? = try parseOptional(dict, key: "log_window", label: "Scenario")

    let personasRaw: [[String: Any]] = try parseRequired(
      dict, key: "personas", label: "Scenario")
    let phasesRaw: [[String: Any]] = try parseRequired(
      dict, key: "phases", label: "Scenario")

    let personas = try personasRaw.map { try mapPersona($0) }
    if personas.count != agentCount {
      throw validationError(
        String(localized: "agents (%lld) does not match personas count (%lld)"),
        agentCount, personas.count)
    }

    let phases = try phasesRaw.enumerated().map { index, raw in
      try mapPhase(raw, index: index)
    }

    let extraData = try collectExtraData(from: dict)

    return Scenario(
      id: id, name: name, description: description,
      language: language,
      simulationLanguage: simulationLanguage,
      agentCount: agentCount, rounds: rounds, context: context,
      personas: personas, phases: phases, logWindow: logWindow, extraData: extraData
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
    let name: String = try parseRequired(dict, key: "name", label: "Persona")
    let description: String =
      try parseOptional(
        dict, key: "description", label: "Persona") ?? ""
    return Persona(name: name, description: description)
  }

  /// Strict-throw on unknown, mirroring PhaseType. See issue #108 / #211.
  /// Wrong-type routes through `parseOptional<String>` so the error message
  /// matches the unified format used elsewhere in the loader.
  private func parseAssignTarget(_ dict: [String: Any], label: String) throws -> AssignTarget? {
    guard let str: String = try parseOptional(dict, key: "target", label: label) else {
      return nil
    }
    guard let parsed = AssignTarget(rawValue: str) else {
      throw validationError(
        String(localized: "%@ has invalid target: '%@'. Use 'all' or 'random_one'."),
        label, str)
    }
    return parsed
  }

  private func parsePairing(_ dict: [String: Any], label: String) throws -> PairingStrategy? {
    guard let str: String = try parseOptional(dict, key: "pairing", label: label) else {
      return nil
    }
    guard let parsed = PairingStrategy(rawValue: str) else {
      throw validationError(
        String(localized: "%@ has invalid pairing: '%@'. Use 'round_robin'."),
        label, str)
    }
    return parsed
  }

  private func parseLogic(_ dict: [String: Any], label: String) throws -> ScoreCalcLogic? {
    guard let str: String = try parseOptional(dict, key: "logic", label: label) else {
      return nil
    }
    guard let parsed = ScoreCalcLogic(rawValue: str) else {
      let allowed = ScoreCalcLogic.allCases.map(\.rawValue).joined(separator: ", ")
      throw validationError(
        String(localized: "%@ has invalid logic: '%@'. Expected one of: %@."),
        label, str, allowed)
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

    let target = try parseAssignTarget(dict, label: label)
    let outputSchema = try parseOutputSchema(dict, label: label)
    let pairing = try parsePairing(dict, label: label)
    let logic = try parseLogic(dict, label: label)

    // speak_each rounds → subRounds
    let subRounds: Int? = try parseOptional(dict, key: "rounds", label: label)

    // Conditional-specific fields (`if:` expression + `then:` / `else:` sub-phase arrays).
    // Recursively descend with depth+1 so nested conditional is rejected here.
    let condition: String? = try parseOptional(dict, key: "if", label: label)
    let thenPhases = try mapBranch(
      dict["then"], branchLabel: "then", parentLabel: label, depth: depth)
    let elsePhases = try mapBranch(
      dict["else"], branchLabel: "else", parentLabel: label, depth: depth)

    // event_inject-specific fields. `probability` accepts Int → Double so
    // boundary literals (`0` / `1`) round-trip naturally; `as` is the
    // variable name written by the handler.
    let probability = try parseOptionalDoubleAcceptingInt(dict, key: "probability", label: label)
    let eventVariable: String? = try parseOptional(dict, key: "as", label: label)

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
      elsePhases: elsePhases,
      probability: probability,
      eventVariable: eventVariable
    )
  }

  private func parsePhaseType(
    _ dict: [String: Any], label: String, depth: Int
  ) throws -> PhaseType {
    guard let typeString = dict["type"] as? String else {
      throw validationError(String(localized: "%@ missing 'type'"), label)
    }
    guard let phaseType = PhaseType(rawValue: typeString) else {
      throw validationError(
        String(localized: "%@ has invalid type: '%@'"), label, typeString)
    }
    if phaseType == .conditional && depth > 0 {
      throw validationError(
        String(
          localized:
            "%@: nested 'conditional' inside another conditional is not allowed (depth-1 rule)."),
        label)
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
      throw validationError(
        String(localized: "%@: field 'output' must be a dictionary of String values, got %@"),
        label, String(describing: type(of: raw)))
    }
    var result: [String: String] = [:]
    for (key, value) in output {
      guard let str = value as? String else {
        throw validationError(
          String(localized: "%@: output schema value for '%@' must be String, got %@"),
          label, key, String(describing: type(of: value)))
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
      throw validationError(
        String(localized: "%@: '%@' must be an array of phase objects"),
        parentLabel, branchLabel)
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
        throw validationError(
          String(
            localized:
              "Top-level field '%@': array-of-dict values must all be String. Quote non-string values (e.g. `majority: \"1\"`)."
          ),
          key)
      }
      if arr.allSatisfy({ $0 is String }) {
        return .array(arr.compactMap { $0 as? String })
      }
      throw validationError(
        String(
          localized:
            "Top-level field '%@': mixed-type arrays are not supported. Use a pure [String] or [[String: String]]."
        ),
        key)
    }
    if let dict = value as? [String: String] {
      return .dictionary(dict)
    }
    if value is [String: Any] {
      throw validationError(
        String(
          localized:
            "Top-level field '%@': dictionary values must all be String. Quote non-string values."),
        key)
    }
    throw validationError(
      String(localized: "Top-level field '%@' has unsupported type %@. Supported shapes: %@."),
      key, String(describing: type(of: value)), Self.supportedExtraDataShapes)
  }
}

/// Builds a ``SimulationError/scenarioValidationFailed(_:)`` from a localized
/// format string and its arguments. Collapses the `String(format:)` wrapper at
/// every call site so each throw stays a single `String(localized:)` literal —
/// xcstringstool still extracts it as Form B (see `.claude/rules/i18n.md`).
///
/// File-scope (not a method) so it stays out of `ScenarioLoader`'s
/// `type_body_length` budget; `nonisolated` because top-level functions inherit
/// `MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION` and the `nonisolated`
/// loader calls it synchronously.
nonisolated private func validationError(
  _ format: String, _ arguments: CVarArg...
) -> SimulationError {
  .scenarioValidationFailed(String(format: format, arguments: arguments))
}
