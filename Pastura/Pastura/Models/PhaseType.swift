import Foundation

/// The type of a simulation phase, determining how it is processed.
///
/// LLM phases (`speakAll`, `speakEach`, `vote`, `choose`, `reflect`,
/// `whisper`) require LLM inference. Code phases (`scoreCalc`, `assign`,
/// `eliminate`, `summarize`, `eventInject`, `relationshipUpdate`) are
/// processed deterministically by the engine. `conditional` is a
/// control-flow phase: the handler itself does no inference, but its
/// sub-phases may be of any type.
nonisolated public enum PhaseType: String, Codable, Sendable, CaseIterable {
  // Adding a new phase type? Follow the full checklist in
  // .claude/rules/engine.md § "Adding a new `PhaseType`" — this enum is the
  // first edit (new case + `requiresLLM`), but that rule is path-scoped to
  // Engine/**·LLM/** and won't auto-load here.
  case speakAll = "speak_all"
  case speakEach = "speak_each"
  case vote
  case choose
  case reflect
  case whisper
  case scoreCalc = "score_calc"
  case assign
  case eliminate
  case summarize
  case conditional
  case eventInject = "event_inject"
  case relationshipUpdate = "relationship_update"
  case narrate

  /// Whether this phase type requires LLM inference.
  ///
  /// `conditional` returns `false` because the handler evaluates a DSL
  /// expression and dispatches to sub-phases — no LLM call is made by the
  /// conditional itself. The sub-phases' `requiresLLM` determines whether
  /// the enclosing branch requires inference; consumers that need the
  /// effective LLM cost of a conditional must walk `thenPhases` / `elsePhases`
  /// (see `ScenarioLoader.estimateInferenceCount`).
  ///
  /// `eventInject` returns `false`: the handler picks a random string from
  /// scenario `extraData` and writes it into `state.variables` — no LLM
  /// call. Subsequent prompt phases reference the injected value via the
  /// `as:` variable name (default `current_event`).
  ///
  /// `reflect` returns `true`: each agent runs an LLM inference to privately
  /// update a short note about the situation (canonical `note` output field),
  /// so it costs one inference per agent per round like `speakAll` / `vote`.
  ///
  /// `whisper` returns `true`: pairs of active agents privately exchange
  /// statements (hidden from other agents' prompts), each utterance costing
  /// one LLM inference.
  ///
  /// `relationshipUpdate` returns `false`: the handler deterministically
  /// updates a per-agent affinity matrix from vote / choose history and
  /// injects a natural-language summary — no LLM call (#910).
  ///
  /// `narrate` returns `true`: a single LLM inference per round makes a
  /// commentator persona narrate the round's highlight (canonical `commentary`
  /// output). Unlike the per-agent LLM phases it costs exactly one inference
  /// per round regardless of agent count — the narrator is not a participant
  /// (#909).
  public var requiresLLM: Bool {
    switch self {
    case .speakAll, .speakEach, .vote, .choose, .reflect, .whisper, .narrate:
      return true
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
      .relationshipUpdate:
      return false
    }
  }
}
