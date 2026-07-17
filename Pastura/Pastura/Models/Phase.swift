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

  /// Per-phase soft cap on the number of sentences in an agent's primary
  /// `statement` output (the YAML `max_sentences:` key), overriding the
  /// global default of 3 sentences for this phase only.
  ///
  /// `nil` means the phase uses the global default. `ScenarioValidator`
  /// enforces the accepted range 1…6. Applied by `PromptBuilder` as a
  /// **prompt-side** brevity rule on the statement field only — it does not
  /// constrain `inner_thought`, and code phases (which emit no statement)
  /// simply never surface the rule.
  ///
  /// Empirically a **ja lever**: a Stage-0 harness A/B (#881) found ja
  /// statement length responds bidirectionally to the cap (cap 1/3/6 →
  /// ~1.0/1.4/1.9 sentences) while en is near-inert (the model already
  /// writes a single sentence). Complements phase-`prompt` content
  /// scaffolding — the cap lifts the ceiling so a scaffolded finale is not
  /// clipped by the global 3-sentence rule.
  public let maxSentences: Int?

  /// Whether `event_inject` draws **without replacement** across a run (the
  /// YAML `no_repeat:` key).
  ///
  /// `nil` / `false` keeps the default with-replacement behavior
  /// (`randomElement()` each round, so a multi-round scenario can re-draw the
  /// same event). `true` tracks already-drawn events per event variable in
  /// ``SimulationState/drawnEvents`` and draws from the remainder, resetting to
  /// the full pool once every entry has been drawn — a late repeat after
  /// exhaustion beats silently blanking `{current_event}` mid-scenario.
  ///
  /// Opt-in so existing scenarios (e.g. word_wolf `mid_game_announcements`,
  /// probability < 1.0) are byte-for-byte unaffected. See #1006.
  public let noRepeat: Bool?

  /// Short voice/persona descriptor for a `narrate` phase's commentator (the
  /// YAML `narrator:` key, e.g. `"熱血なスポーツ実況"`).
  ///
  /// `nil` falls back to the Engine-owned default commentator voice. This
  /// shapes only the narrator's *voice* — it is injected into a fixed
  /// Engine-owned system-prompt template that always carries the factuality +
  /// brevity guardrails, so an author cannot override those guardrails through
  /// this field. YAML-only (no visual editor field in v1), but round-trips
  /// through the editor's dual buffer like `vote_against` / `action_deltas`.
  /// See #909.
  public let narrator: String?

  /// Payoff table for a `score_calc` phase whose `logic` is `pairwise_payoff`
  /// (the YAML `payoff:` key, a list of `{when: [String], points: [Int]}`
  /// rows). See `PayoffRule` and ADR-027.
  ///
  /// `nil` for every other logic. A `pairwise_payoff` phase with no rows (or
  /// none satisfiable by the `choose` options) is a guaranteed no-op, flagged
  /// by the semantic linter (R20a). YAML-only (no visual editor field), but
  /// round-trips through the editor's dual buffer like `narrator` /
  /// `action_deltas`.
  public let payoff: [PayoffRule]?

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
    actionDeltas: [String: Int]? = nil,
    maxSentences: Int? = nil,
    noRepeat: Bool? = nil,
    narrator: String? = nil,
    payoff: [PayoffRule]? = nil
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
    self.maxSentences = maxSentences
    self.noRepeat = noRepeat
    self.narrator = narrator
    self.payoff = payoff
  }

  /// The schema's required keys as a `Set`, or an empty set when the
  /// phase has no output schema (code phases). Handlers pass this to
  /// ``JSONResponseParser/parse(_:expectedKeys:)`` via `LLMCaller.call`
  /// to enable the A2 schema-aware repair guard (#194).
  public var outputSchemaKeys: Set<String> {
    Set(outputSchema?.keys ?? [:].keys)
  }
}
