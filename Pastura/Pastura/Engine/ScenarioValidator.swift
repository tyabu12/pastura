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
  /// a `then:` or `else:` branch.
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
