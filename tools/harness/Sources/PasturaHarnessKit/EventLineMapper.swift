import Foundation
import PasturaCore

/// Maps Engine `SimulationEvent` values to flat JSONL ``EventLine``s.
package enum EventLineMapper {
  /// Returns the line for `event`, or `nil` for the one deliberately
  /// skipped kind: `agentOutputStream` deltas are redundant with the final
  /// `agentOutput` and would bloat the log by orders of magnitude.
  package static func map(
    _ event: SimulationEvent, t: Double, attempt: Int
  ) -> EventLine? {
    switch event {
    case .agentOutputStream:
      return nil
    case .roundStarted(let round, let totalRounds):
      return EventLine(
        t: t, attempt: attempt, event: "round_started", round: round,
        totalRounds: totalRounds)
    case .roundCompleted(let round, let scores):
      return EventLine(
        t: t, attempt: attempt, event: "round_completed", round: round,
        scores: scores)
    case .phaseStarted(let phaseType, let phasePath):
      return EventLine(
        t: t, attempt: attempt, event: "phase_started",
        phaseType: phaseType.rawValue, phasePath: phasePath)
    case .phaseCompleted(let phaseType, let phasePath):
      return EventLine(
        t: t, attempt: attempt, event: "phase_completed",
        phaseType: phaseType.rawValue, phasePath: phasePath)
    case .agentOutput(let agent, let output, let phaseType):
      return EventLine(
        t: t, attempt: attempt, event: "agent_output", agent: agent,
        phaseType: phaseType.rawValue, fields: output.fields,
        rawText: output.rawText)
    default:
      return mapCodeAndLifecycle(event, t: t, attempt: attempt)
    }
  }

  // Split from `map` to respect function_body_length under --strict. Flat
  // one-arm-per-event dispatch (no nested logic), so the cyclomatic-complexity
  // waiver matches the same shape allowed in `PhaseGlyph` / `PhaseDisplayName`.
  // swiftlint:disable:next cyclomatic_complexity
  private static func mapCodeAndLifecycle(
    _ event: SimulationEvent, t: Double, attempt: Int
  ) -> EventLine? {
    switch event {
    case .scoreUpdate(let scores):
      return EventLine(t: t, attempt: attempt, event: "score_update", scores: scores)
    case .elimination(let agent, let voteCount):
      return EventLine(
        t: t, attempt: attempt, event: "elimination", agent: agent,
        voteCount: voteCount)
    case .assignment(let agent, let value):
      return EventLine(
        t: t, attempt: attempt, event: "assignment", agent: agent, value: value)
    case .sharedAssignment(let value):
      // Shared お題 for the whole round (#939) — distinct event name so
      // `jsonl_to_demo_replay.py` can tell it apart from per-agent `assignment`
      // (word wolf).
      return EventLine(
        t: t, attempt: attempt, event: "shared_assignment", value: value)
    case .summary(let text):
      return EventLine(t: t, attempt: attempt, event: "summary", value: text)
    case .relationshipUpdate(let relationships):
      // Raw affinity matrix (#910) — the natural-language summary the agents
      // see is prompt-side only, so the transcript carries the numbers.
      return EventLine(
        t: t, attempt: attempt, event: "relationship_update", relationships: relationships)
    case .voteResults(let votes, let tallies):
      return EventLine(
        t: t, attempt: attempt, event: "vote_results", votes: votes,
        tallies: tallies)
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      return EventLine(
        t: t, attempt: attempt, event: "pairing_result", agent: agent1,
        agent2: agent2, action1: action1, action2: action2)
    case .conditionalEvaluated(let condition, let result):
      return EventLine(
        t: t, attempt: attempt, event: "conditional_evaluated",
        condition: condition, result: result)
    case .eventInjected(let injected):
      return EventLine(t: t, attempt: attempt, event: "event_injected", value: injected)
    default:
      return mapProgressAndTermination(event, t: t, attempt: attempt)
    }
  }

  private static func mapProgressAndTermination(
    _ event: SimulationEvent, t: Double, attempt: Int
  ) -> EventLine? {
    switch event {
    case .simulationCompleted:
      return EventLine(t: t, attempt: attempt, event: "simulation_completed")
    case .simulationPaused(let round, let phasePath):
      return EventLine(
        t: t, attempt: attempt, event: "simulation_paused", round: round,
        phasePath: phasePath)
    case .error(let error):
      return EventLine(
        t: t, attempt: attempt, event: "error", error: String(describing: error))
    case .inferenceStarted(let agent):
      return EventLine(t: t, attempt: attempt, event: "inference_started", agent: agent)
    case .inferenceCompleted(let agent, let durationSeconds, let tokenCount):
      return EventLine(
        t: t, attempt: attempt, event: "inference_completed", agent: agent,
        durationSeconds: durationSeconds, tokenCount: tokenCount)
    case .languageMismatch(let agent, let detected, let expected):
      return EventLine(
        t: t, attempt: attempt, event: "language_mismatch", agent: agent,
        detected: detected, expected: expected)
    case .roundCheckpoint:
      // Internal resume-persistence snapshot (full SimulationState) — not part
      // of the transcript surface, so it produces no line.
      return nil
    case .roundStarted, .roundCompleted, .phaseStarted, .phaseCompleted,
      .agentOutput, .agentOutputStream, .scoreUpdate, .elimination,
      .assignment, .sharedAssignment, .summary, .relationshipUpdate, .voteResults,
      .pairingResult, .conditionalEvaluated, .eventInjected:
      // Handled by the earlier tiers; unreachable here. Listed explicitly
      // (no `default:`) so a NEW SimulationEvent case breaks compilation in
      // this switch — the compile-time canary the upstream tiers' `default:`
      // forwarding would otherwise lose.
      return nil
    }
  }
}
