import Foundation

/// Single source of truth for the `{token}` placeholders the Engine injects
/// into LLM prompt / summarize-template strings at run time.
///
/// Consumed by `BundledPresetPlaceholderCoverageTests` to fail CI when a
/// bundled preset (or the Editor's advertised vocabulary) references a
/// placeholder that **no** handler ever supplies — the failure mode behind
/// #890 (`{assigned_word}` used by `word_wolf` but injected by nothing).
///
/// - Important: membership here only proves a token is *known to some
///   prompt-build site*, NOT that it is supplied in *this* phase context.
///   Supply is per-phase-type (`opponent_name` → choose round-robin only;
///   `candidates` → vote only; `assigned` / `assigned_word` → the 5
///   per-persona LLM sites, never summarize/code phases). The guard is
///   deliberately phase-context-blind — it catches the "supplied by no
///   handler at all" class, which is the one that produced #890. The
///   narrower "supplied by sibling handlers but omitted by one" class
///   (#862) needs per-phase-availability modeling and is out of scope.
///   Do not over-trust a green result as "every placeholder resolves in
///   every phase it appears in".
nonisolated enum PromptPlaceholders {
  /// Every placeholder name a handler can inject into a prompt at run time.
  ///
  /// When a new handler placeholder is added, extend this set in the same
  /// change so the coverage guard stays authoritative.
  static let engineSupplied: Set<String> = [
    "scoreboard",  // SpeakAll/SpeakEach/Vote/Choose/Summarize
    "conversation_log",  // SpeakAll/SpeakEach/Vote/Choose/Summarize
    "current_round",  // SimulationRunner (per-round)
    "candidates",  // VoteHandler
    "opponent_name",  // ChooseHandler (round-robin)
    "assigned",  // canonical per-persona assign value (#890)
    "assigned_word",  // backward-compat alias of `assigned` (#890)
    "assigned_topic",  // AssignHandler (all mode — shared value)
    "vote_results",  // VoteHandler → Summarize
    "wolf_name",  // AssignHandler (random_one mode) → Summarize
    "current_event"  // EventInjectHandler (default event variable)
  ]
}
