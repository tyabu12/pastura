import Foundation

/// Validates a ``Scenario`` against execution limits before running.
///
/// Enforces agent count (2–10), round count (≤30), estimated inference
/// count (warn >50, error >100), and phase-field semantics (e.g.,
/// assign-phase target/source compatibility) to prevent runaway or
/// misconfigured simulations.
nonisolated struct ScenarioValidator: Sendable {

  /// The result of scenario validation.
  struct ValidationResult: Sendable {
    /// Non-fatal warnings (e.g., high inference count).
    let warnings: [String]

    /// The estimated total number of LLM inferences.
    let estimatedInferences: Int
  }

  /// Validates a scenario against execution limits.
  ///
  /// - Parameter scenario: The scenario to validate.
  /// - Returns: A ``ValidationResult`` with any warnings and the inference estimate.
  /// - Throws: ``SimulationError/scenarioValidationFailed(_:)`` if limits are exceeded.
  func validate(_ scenario: Scenario) throws -> ValidationResult {
    // Agent count limits (checked first for clearer error messages)
    if scenario.agentCount < 2 {
      throw SimulationError.scenarioValidationFailed(
        "Agent count (\(scenario.agentCount)) is below minimum of 2"
      )
    }
    if scenario.agentCount > 10 {
      throw SimulationError.scenarioValidationFailed(
        "Agent count (\(scenario.agentCount)) exceeds maximum of 10"
      )
    }

    // Persona count must match agentCount
    if scenario.personas.count != scenario.agentCount {
      throw SimulationError.scenarioValidationFailed(
        "Persona count (\(scenario.personas.count)) does not match agent count (\(scenario.agentCount))"
      )
    }

    // Round count limit
    if scenario.rounds > 30 {
      throw SimulationError.scenarioValidationFailed(
        "Round count (\(scenario.rounds)) exceeds maximum of 30"
      )
    }

    // Inference count estimation
    let estimated = ScenarioLoader.estimateInferenceCount(scenario)

    if estimated > 100 {
      throw SimulationError.scenarioValidationFailed(
        "Estimated inferences (\(estimated)) exceeds maximum of 100"
      )
    }

    try validatePhases(scenario)

    var warnings: [String] = []
    if estimated > 50 {
      warnings.append(
        "High inference count (\(estimated)). Simulation may take several minutes."
      )
    }

    return ValidationResult(warnings: warnings, estimatedInferences: estimated)
  }

  /// Strict validation gate for commit-to-persist callsites
  /// (`ImportViewModel.save()` / `ScenarioEditorViewModel.save()`).
  ///
  /// Runs every check `validate(_:)` runs, then adds the canonical
  /// primary-field requirement: every LLM phase must declare its
  /// ``ScenarioConventions/primaryField(for:)`` key in `output:`. The
  /// engine and UI key on those canonical fields, so a scenario that
  /// omits them silently breaks (empty conversation log, blank UI rows,
  /// `options[0]` fallback for choose). Surfacing the error at commit
  /// time keeps already-persisted scenarios runnable while preventing
  /// new ones from entering the database in the broken shape.
  func validateForCommit(_ scenario: Scenario) throws -> ValidationResult {
    let result = try validate(scenario)
    try validateCanonicalPrimaryFields(scenario)
    return result
  }

  /// Enforces ``ScenarioConventions/primaryField(for:)`` for LLM phases.
  /// Code phases are exempt (the conventions table returns `nil` and the
  /// loop skips them).
  private func validateCanonicalPrimaryFields(_ scenario: Scenario) throws {
    for (index, phase) in scenario.phases.enumerated() {
      guard let canonical = ScenarioConventions.primaryField(for: phase.type) else {
        continue
      }
      let schema = phase.outputSchema ?? [:]
      if schema[canonical] == nil {
        throw SimulationError.scenarioValidationFailed(
          String(
            localized:
              "Phase \(index + 1) (\(phase.type.rawValue)) requires field '\(canonical)' in output."
          )
        )
      }
    }
  }

  /// Per-phase semantic checks beyond execution-limit validation.
  ///
  /// Covers `assign` target/source shape compatibility and `conditional`
  /// branch well-formedness. Unknown `target` values are caught earlier by
  /// `ScenarioLoader` (compile-time enforced via `AssignTarget`).
  private func validatePhases(_ scenario: Scenario) throws {
    for (index, phase) in scenario.phases.enumerated() {
      switch phase.type {
      case .assign:
        try validateAssignPhase(phase, index: index, scenario: scenario)
      case .conditional:
        try validateConditionalPhase(phase, index: index, scenario: scenario, depth: 0)
      case .speakAll, .speakEach, .vote, .choose, .scoreCalc, .eliminate, .summarize:
        break
      case .eventInject:
        try validateEventInjectShape(
          phase, label: "Phase \(index + 1) (event_inject)", scenario: scenario)
      }
    }
  }

  private func validateAssignPhase(
    _ phase: Phase, index: Int, scenario: Scenario
  ) throws {
    try validateAssignPhaseShape(
      phase, label: "Phase \(index + 1) (assign)", scenario: scenario)
  }

  /// Enforces the conditional-phase invariants that the construction-time
  /// `Phase` initializer cannot express:
  /// - `condition` must be non-empty (empty expression would throw at
  ///   evaluator parse time anyway, but failing fast here is clearer).
  /// - At least one of `thenPhases` / `elsePhases` must be non-empty
  ///   (otherwise the phase is a no-op with extra overhead).
  /// - `depth > 0` blocks nested `.conditional` — the loader has the same
  ///   check on the YAML path, and this covers non-YAML construction (tests,
  ///   editors, future migrations).
  private func validateConditionalPhase(
    _ phase: Phase, index: Int, scenario: Scenario, depth: Int
  ) throws {
    let phaseLabel = "Phase \(index + 1) (conditional)"
    let trimmedCondition = (phase.condition ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    if trimmedCondition.isEmpty {
      throw SimulationError.scenarioValidationFailed(
        "\(phaseLabel): missing or empty 'if' expression."
      )
    }

    let thenCount = phase.thenPhases?.count ?? 0
    let elseCount = phase.elsePhases?.count ?? 0
    if thenCount == 0 && elseCount == 0 {
      throw SimulationError.scenarioValidationFailed(
        "\(phaseLabel): must have at least one sub-phase in 'then' or 'else'."
      )
    }

    if depth > 0 {
      throw SimulationError.scenarioValidationFailed(
        "\(phaseLabel): nested 'conditional' inside another conditional is "
          + "not allowed (depth-1 rule)."
      )
    }

    try validateBranch(
      phase.thenPhases ?? [], parentLabel: phaseLabel, branchLabel: "then",
      scenario: scenario)
    try validateBranch(
      phase.elsePhases ?? [], parentLabel: phaseLabel, branchLabel: "else",
      scenario: scenario)
  }

  /// Recursively validates each sub-phase in a conditional branch.
  ///
  /// Rejects nested `.conditional` (depth-1 rule) and applies the same
  /// semantic checks we run at the top level — e.g., an `assign` phase
  /// with mismatched target/source shape still errors when buried inside
  /// a `then:` or `else:` branch. `event_inject` is allowed inside a
  /// branch (consistent with assign / score_calc) and gets the same
  /// shape-check it would receive at the top level.
  private func validateBranch(
    _ phases: [Phase], parentLabel: String, branchLabel: String, scenario: Scenario
  ) throws {
    for (subIndex, subPhase) in phases.enumerated() {
      let subLabel = "\(parentLabel) \(branchLabel)[\(subIndex + 1)]"
      if subPhase.type == .conditional {
        throw SimulationError.scenarioValidationFailed(
          "\(subLabel) is another conditional, which is not allowed (depth-1 rule)."
        )
      }
      if subPhase.type == .assign {
        try validateAssignPhaseShape(subPhase, label: subLabel, scenario: scenario)
      }
      if subPhase.type == .eventInject {
        try validateEventInjectShape(subPhase, label: subLabel, scenario: scenario)
      }
    }
  }

  /// Shared shape-check for event_inject phases, callable from both the
  /// top-level path and from inside a conditional branch.
  ///
  /// Enforces:
  /// - `source` must be present and non-empty (the handler's no-op
  ///   fallback exists for the case where extraData lookup fails at
  ///   runtime, but a curator who wrote `event_inject` clearly meant
  ///   to fire — failing fast at validation is friendlier).
  /// - `extraData[source]` must be `.array` (a list of strings).
  ///   v1 deliberately narrows to this shape; `[String:String]` /
  ///   `.string` etc. would have natural meanings (per-event metadata,
  ///   single fixed event for testing) but expand the type surface
  ///   without curator demand. The error message points at the v1
  ///   workaround so curators don't get stuck.
  /// - `probability` (when set) must lie in `[0.0, 1.0]`. The handler
  ///   would still produce well-defined behavior outside this range
  ///   (`< 0` never fires, `>= 1.0` always fires), but a curator who
  ///   wrote `probability: 1.5` almost certainly mistyped — surfacing
  ///   it early is friendlier than silent over-fire.
  private func validateEventInjectShape(
    _ phase: Phase, label: String, scenario: Scenario
  ) throws {
    let sourceKey = (phase.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sourceKey.isEmpty else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): missing 'source'. event_inject requires a 'source' key naming "
          + "a top-level YAML field that lists the event strings."
      )
    }
    guard let sourceValue = scenario.extraData[sourceKey] else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): source '\(sourceKey)' not found in scenario data. "
          + "Add a top-level '\(sourceKey)' field to the scenario YAML."
      )
    }
    switch sourceValue {
    case .array(let entries):
      // Empty array silently produces probability-miss-equivalent output
      // at runtime (handler writes "" and emits .eventInjected(nil)),
      // which a curator cannot distinguish from a string of unlucky rolls.
      // Reject early so the misconfiguration surfaces at scenario load.
      guard !entries.isEmpty else {
        throw SimulationError.scenarioValidationFailed(
          "\(label): source '\(sourceKey)' is empty. "
            + "event_inject requires at least one string in the list; "
            + "for a single fixed event use ['only_event']."
        )
      }
    case .string, .dictionary, .arrayOfDictionaries:
      throw SimulationError.scenarioValidationFailed(
        "\(label): source '\(sourceKey)' must be a list of strings. "
          + "v1 of event_inject only supports the [String] shape; "
          + "for a single fixed event use ['only_event']."
      )
    }
    if let probability = phase.probability {
      guard (0.0...1.0).contains(probability) else {
        throw SimulationError.scenarioValidationFailed(
          "\(label): probability \(probability) is out of range. "
            + "Must be between 0.0 and 1.0 inclusive."
        )
      }
    }
  }

  /// Shared shape-check for assign phases, callable from both the top-level
  /// and the nested branch paths.
  private func validateAssignPhaseShape(
    _ phase: Phase, label: String, scenario: Scenario
  ) throws {
    // Phases without a `source` reference persona indices instead of extraData
    // — nothing to shape-check.
    guard let sourceKey = phase.source else { return }

    // The Visual Editor now round-trips extraData (#129), so a missing key
    // here means the scenario YAML genuinely lacks the referenced field —
    // the assign would silently no-op at runtime. Surface it early.
    guard let sourceValue = scenario.extraData[sourceKey] else {
      throw SimulationError.scenarioValidationFailed(
        "\(label): source '\(sourceKey)' not found in scenario data. "
          + "Add a top-level '\(sourceKey)' field to the scenario YAML."
      )
    }
    let effectiveTarget = phase.target ?? .all
    switch effectiveTarget {
    case .all:
      switch sourceValue {
      case .array, .string:
        return
      case .arrayOfDictionaries, .dictionary:
        throw SimulationError.scenarioValidationFailed(
          "\(label): source '\(sourceKey)' contains grouped values (e.g., majority/minority pairs). "
            + "Use target: random_one to distribute these. "
            + "Use target: all only for a flat list of strings or a single string."
        )
      }
    case .randomOne:
      switch sourceValue {
      case .arrayOfDictionaries:
        return
      case .array, .string, .dictionary:
        throw SimulationError.scenarioValidationFailed(
          "\(label): source '\(sourceKey)' must be a list of grouped values "
            + "(e.g., majority/minority pairs) when target is random_one."
        )
      }
    }
  }
}
