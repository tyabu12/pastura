import Foundation

/// Localized, human-readable descriptions for the `{token}` placeholders an
/// author can insert into a phase prompt / summarize template.
///
/// Views-layer **display** single source of truth — the *availability* of each
/// token stays in Engine's ``PlaceholderAvailability`` (Dependency Rules: Engine
/// holds no user-facing display strings, to keep it SPM-extractable). The
/// variable-insert sheet (`VariablePickerSheet`) reads this to caption each
/// token; the token identifier itself is shown verbatim (never localized).
///
/// Each description routes through `String(localized:)` so it lands in
/// `Localizable.xcstrings` and gets a `ja` translation (CLAUDE.md "User-facing
/// String literals").
///
/// ## Coverage
///
/// `PlaceholderDisplayTests` asserts that every token in the union of
/// ``PlaceholderAvailability/supplied(for:chooseRoundRobin:)`` over all phase
/// types, plus ``PlaceholderAvailability/crossPhaseStateReadable``, has a
/// non-nil description here — so a newly engine-supplied placeholder fails the
/// test until it is described.
enum PlaceholderDisplay {

  // Pure token→description mapping. The 23-case count exceeds SwiftLint's
  // cyclomatic threshold but carries no branching logic.
  // swiftlint:disable cyclomatic_complexity
  /// A short localized description of `token`, or `nil` when `token` is not a
  /// known engine-supplied placeholder (the caller omits unknown / custom keys).
  static func description(for token: String) -> String? {
    switch token {
    case "scoreboard": return String(localized: "Current scoreboard for all agents")
    case "conversation_log": return String(localized: "The conversation log so far")
    case "current_round": return String(localized: "The current round number")
    case "assigned": return String(localized: "Info assigned to this agent (from an assign phase)")
    case "assigned_word": return String(localized: "The word or topic assigned to this agent")
    case "my_notes": return String(localized: "This agent's own private reflection notes")
    case "relationships": return String(localized: "How this agent feels about the others")
    case "my_mood": return String(localized: "This agent's current mood")
    case "my_whispers": return String(localized: "The whispers this agent exchanged")
    case "candidates": return String(localized: "The list of vote candidates")
    case "vote_results": return String(localized: "The most recent vote results")
    case "opponent_name":
      return String(localized: "The paired opponent's name (round-robin choose)")
    case "whisper_partner": return String(localized: "This round's whisper partner")
    case "whisper_exchange": return String(localized: "The whisper exchange this round")
    case "agent1": return String(localized: "First agent of the pair")
    case "action1": return String(localized: "First agent's chosen action")
    case "agent2": return String(localized: "Second agent of the pair")
    case "action2": return String(localized: "Second agent's chosen action")
    case "score1": return String(localized: "First agent's score")
    case "score2": return String(localized: "Second agent's score")
    case "assigned_topic": return String(localized: "The shared topic assigned to everyone")
    case "wolf_name": return String(localized: "The wolf's name (assigned to one agent)")
    case "current_event": return String(localized: "The event currently in play")
    default: return nil
    }
  }
  // swiftlint:enable cyclomatic_complexity
}
