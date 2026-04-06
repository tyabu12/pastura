import Foundation

/// The execution status of a simulation.
public enum SimulationStatus: String, Codable, Sendable {
  /// The simulation is actively running.
  case running

  /// The simulation is paused and can be resumed.
  case paused

  /// The simulation has finished executing all rounds.
  case completed
}
