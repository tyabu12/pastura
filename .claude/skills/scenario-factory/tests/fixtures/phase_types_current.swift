import Foundation

/// Fixture mirroring the real PhaseType enum's 14 current cases.
/// Used by the census PhaseType-drift tripwire "no drift" test: every phase
/// here is covered by an axis or the scaffolding set, so no NEW-mechanic
/// warning should fire.
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
  case relationshipUpdate = "relationship_update"
  case narrate

  public var requiresLLM: Bool {
    // Dot-prefixed switch patterns must NOT be parsed as new cases.
    switch self {
    case .speakAll, .speakEach, .vote, .choose, .reflect, .whisper, .narrate:
      return true
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
      .relationshipUpdate:
      return false
    }
  }
}
