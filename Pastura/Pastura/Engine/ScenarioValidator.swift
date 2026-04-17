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

  private func validatePhases(_ scenario: Scenario) throws {
    for (index, phase) in scenario.phases.enumerated() {
      guard phase.type == .assign else { continue }

      let phaseLabel = "Phase \(index + 1) (assign)"

      let target = phase.target
      if let target, target != "all", target != "random_one" {
        throw SimulationError.scenarioValidationFailed(
          "\(phaseLabel): unknown target '\(target)'. Use 'all' or 'random_one'."
        )
      }

      // Shape validation requires both a source key and a resolved value.
      // Skip if source is nil or key is absent from extraData (Visual Editor compat).
      guard let sourceKey = phase.source, let sourceValue = scenario.extraData[sourceKey] else {
        continue
      }

      let effectiveTarget = target ?? "all"

      if effectiveTarget == "all" {
        switch sourceValue {
        case .array, .string:
          break
        case .arrayOfDictionaries, .dictionary:
          throw SimulationError.scenarioValidationFailed(
            "\(phaseLabel): source '\(sourceKey)' contains grouped values (e.g., majority/minority pairs). "
              + "Use target: random_one to distribute these. "
              + "Use target: all only for a flat list of strings or a single string."
          )
        }
      } else {
        switch sourceValue {
        case .arrayOfDictionaries:
          break
        case .array, .string, .dictionary:
          throw SimulationError.scenarioValidationFailed(
            "\(phaseLabel): source '\(sourceKey)' must be a list of grouped values "
              + "(e.g., majority/minority pairs) when target is random_one."
          )
        }
      }
    }
  }
}
