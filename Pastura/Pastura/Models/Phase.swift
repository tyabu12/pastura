import Foundation

/// A single phase definition within a scenario.
///
/// Each phase describes one step in a simulation round. The available fields
/// depend on the phase's `type` — LLM phases use `prompt` and `outputSchema`,
/// while code phases use type-specific fields like `logic` or `template`.
nonisolated public struct Phase: Codable, Sendable, Equatable {
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

  /// Target specification for `assign` phases. `nil` defaults to `.all`.
  public let target: AssignTarget?

  /// Whether agents are excluded from voting for themselves in `vote` phases.
  public let excludeSelf: Bool?

  /// Number of sub-rounds for `speak_each` phases. Defaults to 1 if not specified.
  public let subRounds: Int?

  /// Single-comparison condition expression for `conditional` phases.
  ///
  /// Grammar: `Identifier(.Identifier)? OP (Number | "String" | Identifier)` where
  /// `OP` is one of `==`, `!=`, `<`, `<=`, `>`, `>=`. Evaluated by
  /// `ConditionEvaluator` at handler dispatch time. `&&` / `||` combinators
  /// are deliberately not supported in v1 — see follow-up issue.
  public let condition: String?

  /// Sub-phases executed when `condition` evaluates to true. May be `nil`
  /// (then-branch empty, handler no-ops) or an array of any phase type
  /// except `.conditional` itself (depth-1 rule enforced by
  /// `ScenarioValidator` and `ScenarioLoader`).
  public let thenPhases: [Phase]?

  /// Sub-phases executed when `condition` evaluates to false. See
  /// `thenPhases` for shape constraints.
  public let elsePhases: [Phase]?

  public init(
    type: PhaseType,
    prompt: String? = nil,
    outputSchema: [String: String]? = nil,
    options: [String]? = nil,
    pairing: PairingStrategy? = nil,
    logic: ScoreCalcLogic? = nil,
    template: String? = nil,
    source: String? = nil,
    target: AssignTarget? = nil,
    excludeSelf: Bool? = nil,
    subRounds: Int? = nil,
    condition: String? = nil,
    thenPhases: [Phase]? = nil,
    elsePhases: [Phase]? = nil
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
    self.condition = condition
    self.thenPhases = thenPhases
    self.elsePhases = elsePhases
  }

  /// The schema's required keys as a `Set`, or an empty set when the
  /// phase has no output schema (code phases). Handlers pass this to
  /// ``JSONResponseParser/parse(_:expectedKeys:)`` via `LLMCaller.call`
  /// to enable the A2 schema-aware repair guard (#194).
  public var outputSchemaKeys: Set<String> {
    Set(outputSchema?.keys ?? [:].keys)
  }
}
