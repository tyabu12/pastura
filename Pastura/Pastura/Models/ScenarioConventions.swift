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
/// (rendered by ``AgentOutputRow``). Choose binds the canonical field to a
/// GBNF enum constraint (see ``OutputSchema/from(phase:)``) and reads it back
/// directly in ``ChooseHandler``. Vote is similarly read directly by
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
}
