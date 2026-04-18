import Foundation

/// The type of a simulation phase, determining how it is processed.
///
/// LLM phases (`speakAll`, `speakEach`, `vote`, `choose`) require LLM inference.
/// Code phases (`scoreCalc`, `assign`, `eliminate`, `summarize`) are processed
/// deterministically by the engine. `conditional` is a control-flow phase:
/// the handler itself does no inference, but its sub-phases may be of any type.
nonisolated public enum PhaseType: String, Codable, Sendable, CaseIterable {
  case speakAll = "speak_all"
  case speakEach = "speak_each"
  case vote
  case choose
  case scoreCalc = "score_calc"
  case assign
  case eliminate
  case summarize
  case conditional

  /// Whether this phase type requires LLM inference.
  ///
  /// `conditional` returns `false` because the handler evaluates a DSL
  /// expression and dispatches to sub-phases — no LLM call is made by the
  /// conditional itself. The sub-phases' `requiresLLM` determines whether
  /// the enclosing branch requires inference; consumers that need the
  /// effective LLM cost of a conditional must walk `thenPhases` / `elsePhases`
  /// (see `ScenarioLoader.estimateInferenceCount`).
  public var requiresLLM: Bool {
    switch self {
    case .speakAll, .speakEach, .vote, .choose:
      return true
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional:
      return false
    }
  }
}
