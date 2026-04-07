import Foundation

// @MainActor is explicit for Xcode 16.x CI compatibility. See #37.

/// ViewModel for past simulation results.
///
/// Fetches simulations grouped by scenario. When `scenarioId` is empty,
/// loads all scenarios with their simulations for the global results view.
@MainActor @Observable
final class ResultsViewModel {
  private(set) var groups: [ScenarioGroup] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  private let scenarioRepository: any ScenarioRepository
  private let simulationRepository: any SimulationRepository
  private let turnRepository: any TurnRepository

  struct ScenarioGroup: Identifiable {
    let scenarioName: String
    let simulations: [SimulationRecord]
    var id: String { scenarioName }
  }

  init(
    scenarioRepository: any ScenarioRepository,
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository
  ) {
    self.scenarioRepository = scenarioRepository
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
  }

  func load(scenarioId: String) async {
    isLoading = true
    errorMessage = nil

    do {
      if scenarioId.isEmpty {
        // Load all scenarios with simulations
        let scenarios = try await offMain { [scenarioRepository] in
          try scenarioRepository.fetchAll()
        }
        var result: [ScenarioGroup] = []
        for scenario in scenarios {
          let sims = try await offMain { [simulationRepository] in
            try simulationRepository.fetchByScenarioId(scenario.id)
          }
          if !sims.isEmpty {
            result.append(ScenarioGroup(scenarioName: scenario.name, simulations: sims))
          }
        }
        groups = result
      } else {
        // Load simulations for a specific scenario
        let scenario = try await offMain { [scenarioRepository] in
          try scenarioRepository.fetchById(scenarioId)
        }
        let sims = try await offMain { [simulationRepository] in
          try simulationRepository.fetchByScenarioId(scenarioId)
        }
        if !sims.isEmpty {
          groups = [
            ScenarioGroup(
              scenarioName: scenario?.name ?? "Unknown",
              simulations: sims
            )
          ]
        }
      }
    } catch {
      errorMessage = "Failed to load results: \(error.localizedDescription)"
    }

    isLoading = false
  }

  /// Loads all turn records for a simulation (for result detail replay).
  func loadTurns(simulationId: String) async -> [TurnRecord] {
    do {
      return try await offMain { [turnRepository] in
        try turnRepository.fetchBySimulationId(simulationId)
      }
    } catch {
      errorMessage = "Failed to load turns: \(error.localizedDescription)"
      return []
    }
  }

  /// Decodes the SimulationState from a record's stateJSON.
  func decodeState(from record: SimulationRecord) -> SimulationState? {
    guard let data = record.stateJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SimulationState.self, from: data)
  }
}
