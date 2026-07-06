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

  /// Boolean condition expression for `conditional` phases.
  ///
  /// Single-comparison primitive (`Identifier(.Identifier)? OP Operand`)
  /// composed with `&&` / `||` and parenthesized grouping. Precedence:
  /// comparison > `&&` > `||`, both combinators left-associative.
  /// Parsed and evaluated by `ConditionEvaluator`; see that type's doc
  /// comment for the full grammar, derived-variable table, and Swift-
  /// style short-circuit policy.
  public let condition: String?

  /// Sub-phases executed when `condition` evaluates to true. May be `nil`
  /// (then-branch empty, handler no-ops) or an array of any phase type
  /// except `.conditional` itself (depth-1 rule enforced by
  /// `ScenarioValidator` and `ScenarioLoader`).
  public let thenPhases: [Phase]?

  /// Sub-phases executed when `condition` evaluates to false. See
  /// `thenPhases` for shape constraints.
  public let elsePhases: [Phase]?

  /// Fire probability for `event_inject` phases, in `[0.0, 1.0]`.
  ///
  /// `nil` defaults to `1.0` (always fires). The handler uses strict `<`
  /// against `Double.random(in: 0..<1)`, so `0.0` never fires and `1.0`
  /// always fires. The first `Double?`-typed field on `Phase`; the YAML
  /// loader accepts either `0.5` (Double) or `1` (Int) by intentional
  /// coercion — see `ScenarioLoader.parseOptionalDoubleAcceptingInt`.
  public let probability: Double?

  /// Variable name written by `event_inject` phases (the YAML `as:` key).
  ///
  /// `nil` defaults to `"current_event"`. The handler writes the chosen
  /// event string (or the empty string on miss) to
  /// `state.variables[eventVariable ?? "current_event"]` so subsequent
  /// prompt phases can reference it via `{current_event}`.
  public let eventVariable: String?

  /// Affinity delta applied by `relationship_update` phases (the YAML
  /// `vote_against:` key) when another agent voted for the perceiver.
  ///
  /// `nil` means votes are not scored by this phase. Typically negative
  /// (e.g. `-1`) — the perceiver grows wary of whoever voted against them.
  /// Read from `state.lastOutputs[voter].vote` (#910).
  public let voteAgainst: Int?

  /// Per-action affinity deltas for `relationship_update` phases (the YAML
  /// `action_deltas:` map, e.g. `{cooperate: 1, betray: -2}`).
  ///
  /// `nil` means choose actions are not scored by this phase. The key is a
  /// partner's `choose`-phase action value toward the perceiver; the value
  /// is the delta the perceiver applies to that partner. Read from
  /// `Pairing.action1/action2` (#910).
  public let actionDeltas: [String: Int]?

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
    elsePhases: [Phase]? = nil,
    probability: Double? = nil,
    eventVariable: String? = nil,
    voteAgainst: Int? = nil,
    actionDeltas: [String: Int]? = nil
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
    self.probability = probability
    self.eventVariable = eventVariable
    self.voteAgainst = voteAgainst
    self.actionDeltas = actionDeltas
  }

  /// The schema's required keys as a `Set`, or an empty set when the
  /// phase has no output schema (code phases). Handlers pass this to
  /// ``JSONResponseParser/parse(_:expectedKeys:)`` via `LLMCaller.call`
  /// to enable the A2 schema-aware repair guard (#194).
  public var outputSchemaKeys: Set<String> {
    Set(outputSchema?.keys ?? [:].keys)
  }
}
