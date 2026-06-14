import Foundation

/// Naming conventions for scenario authoring.
///
/// LLM phases each have a single canonical primary output field that the
/// engine and UI key on:
///
/// | Phase | Canonical primary field |
/// |-------|-------------------------|
/// | `.speakAll`, `.speakEach` | `statement` |
/// | `.choose` | `action` |
/// | `.vote` | `vote` |
///
/// Speak phases route the canonical field's value into the conversation log
/// (read by ``PromptBuilder``) and into the agent's primary display text
/// (rendered by ``AgentOutputRow``). Choose reads the canonical field back
/// directly in ``ChooseHandler``, which validates it against the phase
/// options at runtime (the value is not grammar-constrained — see
/// ``OutputSchema/from(phase:)`` and ADR-002 §Amendment 2026-06-14). Vote
/// is similarly read directly by
/// ``VoteHandler`` and surfaces composite formatting via
/// ``TurnOutput/primaryText(for:)``.
///
/// Code phases (`.scoreCalc`, `.assign`, `.eliminate`, `.summarize`,
/// `.conditional`, `.eventInject`) emit no LLM output and therefore have no
/// primary field — ``primaryField(for:)`` returns `nil`.
///
/// This convention is enforced at scenario-commit time by
/// ``ScenarioValidator/validateForCommit(_:)``; it is not re-checked at
/// run-time because ``SimulationRunner`` accepts already-persisted scenarios
/// as-is.
nonisolated public enum ScenarioConventions {
  /// Returns the canonical primary output field name expected on `output:`
  /// for the given phase type, or `nil` for code phases that emit no LLM
  /// output.
  ///
  /// Speak phases return `"statement"`, choose returns `"action"`, vote
  /// returns `"vote"`. All other phase types return `nil`.
  public static func primaryField(for phaseType: PhaseType) -> String? {
    switch phaseType {
    case .speakAll, .speakEach:
      return "statement"
    case .choose:
      return "action"
    case .vote:
      return "vote"
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject:
      return nil
    }
  }

  /// Returns the private-thought (secondary) output field name expected on
  /// `output:` for the given LLM phase, or `nil` for code phases.
  ///
  /// Vote returns `"reason"`; every other LLM phase returns `"inner_thought"`.
  /// Both fields are display-only private reasoning (never routed into the
  /// conversation log, so invisible to other agents) — `reason` is simply the
  /// vote-phase spelling of the same concept (vote schemas author
  /// `{ vote, reason }`, speak schemas `{ statement, inner_thought }`). This is
  /// the single source of truth that keeps the THINKING section's content
  /// source consistent across the committed-display path
  /// (``TurnOutput/secondaryText(for:)``) and the live streaming path
  /// (``PartialOutputExtractor`` driven by ``LLMCaller``).
  ///
  /// Phase-aware (not a blind `inner_thought` fallback) so a stray `reason` on
  /// a speak/choose output never leaks into THINKING, and a vote's `reason` is
  /// never dropped in favour of an `inner_thought` vote schemas don't author.
  public static func thoughtField(for phaseType: PhaseType) -> String? {
    switch phaseType {
    case .vote:
      return "reason"
    case .speakAll, .speakEach, .choose:
      return "inner_thought"
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject:
      return nil
    }
  }
}
