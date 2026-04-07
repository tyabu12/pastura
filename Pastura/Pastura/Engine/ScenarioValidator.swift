import Foundation

/// Validates a ``Scenario`` against execution limits before running.
///
/// Enforces agent count (2–10), round count (≤30), and estimated inference
/// count (warn >50, error >100) to prevent runaway simulations.
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
    // Agent count limits
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

    var warnings: [String] = []
    if estimated > 50 {
      warnings.append(
        "High inference count (\(estimated)). Simulation may take several minutes."
      )
    }

    return ValidationResult(warnings: warnings, estimatedInferences: estimated)
  }
}
