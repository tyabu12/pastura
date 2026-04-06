import Foundation

/// A single phase definition within a scenario.
///
/// Each phase describes one step in a simulation round. The available fields
/// depend on the phase's `type` — LLM phases use `prompt` and `outputSchema`,
/// while code phases use type-specific fields like `logic` or `template`.
public struct Phase: Codable, Sendable, Equatable {
  /// The type of this phase, determining how it is processed.
  public let type: PhaseType

  /// The prompt template sent to the LLM. Supports variable expansion
  /// (e.g., `{scoreboard}`, `{opponent_name}`). Required for LLM phases.
  public let prompt: String?

  /// Expected output field names and their type descriptors (e.g., `["action": "string"]`).
  /// Used by `JSONResponseParser` to validate LLM output. Required for LLM phases.
  public let outputSchema: [String: String]?

  /// Available choices for `choose` phases (e.g., `["cooperate", "betray"]`).
  public let options: [String]?

  /// Pairing strategy for `choose` phases (e.g., `.roundRobin`).
  public let pairing: PairingStrategy?

  /// Scoring logic identifier for `score_calc` phases.
  public let logic: ScoreCalcLogic?

  /// Format template for `summarize` phases. Supports variable expansion.
  public let template: String?

  /// Data source key for `assign` phases (e.g., `"topics"`).
  /// References a top-level field in the scenario definition.
  public let source: String?

  /// Target specification for `assign` phases (e.g., `"all"`).
  public let target: String?

  /// Whether agents are excluded from voting for themselves in `vote` phases.
  public let excludeSelf: Bool?

  /// Number of sub-rounds for `speak_each` phases. Defaults to 1 if not specified.
  public let subRounds: Int?

  public init(
    type: PhaseType,
    prompt: String? = nil,
    outputSchema: [String: String]? = nil,
    options: [String]? = nil,
    pairing: PairingStrategy? = nil,
    logic: ScoreCalcLogic? = nil,
    template: String? = nil,
    source: String? = nil,
    target: String? = nil,
    excludeSelf: Bool? = nil,
    subRounds: Int? = nil
  ) {
    self.type = type
    self.prompt = prompt
    self.outputSchema = outputSchema
    self.options = options
    self.pairing = pairing
    self.logic = logic
    self.template = template
    self.source = source
    self.target = target
    self.excludeSelf = excludeSelf
    self.subRounds = subRounds
  }
}
