import Foundation

// Semantic-lint run gate (ADR-024 D5), split from SimulationRunner.swift for
// the 400-line file budget. `nonisolated extension` per swift-isolation
// Pattern 3 (sibling files of a nonisolated type don't inherit its annotation).
nonisolated extension SimulationRunner {

  /// The run gate: structural validation (`ScenarioValidator`) followed by the
  /// semantic lint gate below. Split from `executeSimulation` for the file
  /// budget; behavior is unchanged.
  ///
  /// - Returns: `true` when the run may proceed. On `false` the blocking
  ///   `.error` event has already been emitted.
  static func preflightGate(
    scenario: Scenario, validator: ScenarioValidator,
    emitter: @Sendable (SimulationEvent) -> Void
  ) -> Bool {
    do {
      let result = try validator.validate(scenario)
      for warning in result.warnings {
        emitter(.summary(text: "⚠️ \(warning)"))
      }
    } catch {
      emitter(
        .error(
          error as? SimulationError
            ?? .scenarioValidationFailed(readableDescription(error))))
      return false
    }
    return semanticLintGate(scenario: scenario, emitter: emitter)
  }

  /// Runs the semantic linter (ADR-024) after the structural validator passes.
  ///
  /// `.error` findings block the run exactly like a validation error (emitted
  /// as one aggregated `.scenarioValidationFailed`); `.warning` findings ride
  /// the existing inference-count `.summary("⚠️ …")` channel; `.info` findings
  /// are not surfaced at the run gate.
  ///
  /// - Returns: `true` when the run may proceed, `false` when an error-severity
  ///   finding blocked it (the error event has already been emitted).
  static func semanticLintGate(
    scenario: Scenario, emitter: @Sendable (SimulationEvent) -> Void
  ) -> Bool {
    // The linter is a stateless value, so it's built here rather than plumbed
    // through the runner's parameter list.
    let findings = ScenarioSemanticLinter().lint(scenario)
    let lintErrors = findings.filter { $0.severity == .error }
    if !lintErrors.isEmpty {
      emitter(
        .error(.scenarioValidationFailed(lintErrors.map(\.message).joined(separator: "\n"))))
      return false
    }
    for finding in findings where finding.severity == .warning {
      emitter(.summary(text: "⚠️ \(finding.message)"))
    }
    return true
  }
}
