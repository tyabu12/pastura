import Foundation

/// Fixture simulating a FUTURE engine phase that the census axes don't yet
/// cover. Mirrors the real 12 cases PLUS a fake `futurePhase` case with an
/// explicit raw value — the drift tripwire must surface `future_phase` as a
/// NEW ENGINE MECHANIC. The switch block below carries dot-prefixed patterns
/// (`case .speakAll, .futurePhase:`) to prove the parser ignores them.
nonisolated public enum PhaseType: String, Codable, Sendable, CaseIterable {
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
  case futurePhase = "future_phase"

  public var requiresLLM: Bool {
    switch self {
    case .speakAll, .speakEach, .vote, .choose, .reflect, .whisper, .futurePhase:
      return true
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject:
      return false
    }
  }
}
