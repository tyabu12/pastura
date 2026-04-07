import Foundation

/// Navigation destinations for the app's `NavigationStack`.
///
/// Each case carries the minimum data needed to construct the destination view.
/// Used with `NavigationStack(path:)` for programmatic navigation.
enum Route: Hashable {
  /// Scenario detail screen.
  case scenarioDetail(scenarioId: String)

  /// YAML import screen. Pass an existing scenario ID to edit.
  case importScenario(editingId: String? = nil)

  /// Live simulation execution screen.
  case simulation(scenarioId: String)

  /// Past simulation results list for a scenario.
  case results(scenarioId: String)

  /// Detail view for a specific past simulation run.
  case resultDetail(simulationId: String)
}
