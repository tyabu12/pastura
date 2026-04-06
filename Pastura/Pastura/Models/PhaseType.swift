import Foundation

/// The type of a simulation phase, determining how it is processed.
///
/// LLM phases (`speakAll`, `speakEach`, `vote`, `choose`) require LLM inference.
/// Code phases (`scoreCalc`, `assign`, `eliminate`, `summarize`) are processed
/// deterministically by the engine.
// nonisolated: Models layer must be accessible from any actor (Engine runs off-main).
nonisolated public enum PhaseType: String, Codable, Sendable, CaseIterable {
  case speakAll = "speak_all"
  case speakEach = "speak_each"
  case vote
  case choose
  case scoreCalc = "score_calc"
  case assign
  case eliminate
  case summarize

  /// Whether this phase type requires LLM inference.
  public var requiresLLM: Bool {
    switch self {
    case .speakAll, .speakEach, .vote, .choose:
      return true
    case .scoreCalc, .assign, .eliminate, .summarize:
      return false
    }
  }
}
