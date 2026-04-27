import Foundation

/// Serializable payload for a code-phase event persisted in `code_phase_events`.
///
/// Mirrors the code-phase cases of `SimulationEvent` for durable storage.
/// The App layer consumes `SimulationEvent`s from the Engine and maps them
/// into this type before writing to the database, so the exporter and other
/// consumers can reconstruct per-phase results without replaying events.
///
/// Wire-format stability: adding new cases is backward-compatible under
/// Swift's default `Codable` synthesis for enums (new outer keys are
/// simply unknown to old decoders, which isn't an issue here since readers
/// ship with producers). Renaming or removing a case requires a data
/// migration that rewrites existing `payloadJSON` rows.
nonisolated public enum CodePhaseEventPayload: Codable, Sendable, Equatable {
  /// An agent was eliminated as the result of an `eliminate` phase.
  case elimination(agent: String, voteCount: Int)

  /// Scores were updated by a `score_calc` phase.
  case scoreUpdate(scores: [String: Int])

  /// A textual summary was produced by `summarize` or a scoring logic
  /// (e.g., `wordwolf_judge` verdicts surface here).
  case summary(text: String)

  /// Voting concluded. `votes` maps voter → target; `tallies` maps
  /// candidate → received vote count.
  case voteResults(votes: [String: String], tallies: [String: Int])

  /// One pair's outcome in a `choose` phase with round-robin pairing.
  case pairingResult(agent1: String, action1: String, agent2: String, action2: String)

  /// A value was assigned to an agent by an `assign` phase
  /// (e.g., wolf/villager role in Word Wolf).
  case assignment(agent: String, value: String)

  /// An `event_inject` phase rolled its probability and either selected
  /// a random event string (`event != nil`) or missed (`event == nil`).
  /// The miss case persists explicitly so past-results timelines can
  /// distinguish "phase didn't run" from "phase ran and rolled a miss".
  case eventInjected(event: String?)
}
