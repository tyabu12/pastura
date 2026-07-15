import SwiftUI

extension PhaseEditorSheet {
  // MARK: - Helpers

  // Returned as `String` (not `LocalizedStringKey`) because the consumer is
  // `Text(phaseTypeDescription)` which uses the verbatim-String overload —
  // wrap each branch with `String(localized:)` so the value goes through
  // Bundle resolution before display.
  var phaseTypeDescription: String {
    switch phase.type {
    case .speakAll: return String(localized: "All agents speak simultaneously")
    case .speakEach: return String(localized: "Agents speak in turn (accumulating context)")
    case .vote: return String(localized: "All agents vote for one agent")
    case .choose: return String(localized: "Choose from predefined options")
    case .reflect:
      return String(localized: "Each agent privately updates a short memo about the situation")
    case .whisper:
      return String(
        localized: "Pairs of agents privately whisper to each other (hidden from others)")
    case .scoreCalc: return String(localized: "Calculate scores (code, no LLM)")
    case .assign: return String(localized: "Distribute info to agents (code)")
    case .eliminate: return String(localized: "Remove most-voted agent (code)")
    case .summarize: return String(localized: "Format round summary (code)")
    case .conditional: return String(localized: "Branch on state (code, then/else sub-phases)")
    case .eventInject:
      return String(localized: "Inject a random event from extraData (code, no LLM)")
    case .relationshipUpdate:
      return String(localized: "Update affinity matrix from vote/action history (code, no LLM)")
    case .narrate:
      return String(localized: "A commentator narrates the round's highlight (one LLM call)")
    }
  }
}
