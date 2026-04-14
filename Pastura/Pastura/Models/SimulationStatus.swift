import Foundation

/// The execution status of a simulation.
nonisolated public enum SimulationStatus: String, Codable, Sendable {
  /// The simulation is actively running.
  case running

  /// The simulation is paused and can be resumed.
  case paused

  /// The simulation has finished all rounds successfully.
  case completed

  /// The simulation ended due to an error (LLM load failure, event-pipeline error, etc.).
  /// The error message is surfaced via `SimulationViewModel.errorMessage`; this case
  /// disambiguates failed runs from clean completions at the DB level.
  case failed

  /// The simulation was cancelled before natural completion — user-initiated or
  /// memory-warning induced. Distinguished from `.paused` (resumable) and `.failed`
  /// (errored).
  case cancelled
}
