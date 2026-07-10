import Foundation

// ADR-022 D3 — the ONE `SimulationEvent` → code-phase projection, extracted
// into Models (a legal Models→Models dependency) so both ViewModels derive
// their code-phase semantics from a single source.
//
// The two halves below are a paired unit: their non-nil case sets are
// identical by invariant — a `SimulationEvent` yields a
// `CodePhaseEventPayload` iff it yields a `defaultCodePhaseType`. Keep them in
// lockstep. Both are no-default exhaustive over `SimulationEvent` (ADR-022 D2),
// so a newly added event case fails to compile here until its projection —
// a payload, or an explicit `nil` — is decided. A broken pairing (one half
// non-nil, the other nil) is caught by the D5 executable backstop
// `CrossVMEventParityTests.bothVMsProjectTheSameCodePhaseSemantics`.

nonisolated extension CodePhaseEventPayload {
  /// Projects a `SimulationEvent` to its durable code-phase payload, or `nil`
  /// for events that have no code-phase representation.
  ///
  /// This is the single extraction point the App layer uses to persist
  /// (`SimulationViewModel`) and to render replay lines (`ReplayViewModel`),
  /// replacing the previously-scattered per-arm constructions (ADR-022 P4).
  public init?(event: SimulationEvent) {
    switch event {
    case .scoreUpdate(let scores):
      self = .scoreUpdate(scores: scores)
    case .elimination(let agent, let voteCount):
      self = .elimination(agent: agent, voteCount: voteCount)
    case .assignment(let agent, let value):
      self = .assignment(agent: agent, value: value)
    case .sharedAssignment(let value):
      self = .sharedAssignment(value: value)
    case .summary(let text):
      self = .summary(text: text)
    case .voteResults(let votes, let tallies):
      self = .voteResults(votes: votes, tallies: tallies)
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      self = .pairingResult(
        agent1: agent1, action1: action1, agent2: agent2, action2: action2)
    case .eventInjected(let event):
      self = .eventInjected(event: event)
    // Non-code-phase events have no durable code-phase payload. Listed
    // explicitly (no `default:`) so a new `SimulationEvent` case forces a
    // decision here rather than silently mapping to `nil`.
    case .roundStarted, .roundCompleted, .phaseStarted, .phaseCompleted,
      .agentOutput, .agentOutputStream, .relationshipUpdate,
      .conditionalEvaluated, .simulationCompleted, .roundCheckpoint,
      .simulationPaused, .error, .inferenceStarted, .inferenceCompleted,
      .languageMismatch, .turnSkipped:
      return nil
    }
  }
}

nonisolated extension SimulationEvent {
  /// Fallback phase kind for export/display bucketing when a code-phase event
  /// arrives outside a `phaseStarted` window.
  ///
  /// Consumers prefer the live `currentPhaseType` and read this only as the
  /// `??` fallback (e.g. `.summary` fires from both `SummarizeHandler` and
  /// scoring logics, so a hard-coded phase would mis-bucket the latter).
  ///
  /// No-default exhaustive; `nil` for every non-code-phase case. Its non-nil
  /// case set is identical to ``CodePhaseEventPayload/init(event:)`` by the
  /// paired-nil invariant documented above.
  public var defaultCodePhaseType: PhaseType? {
    switch self {
    case .scoreUpdate: return .scoreCalc
    case .elimination: return .eliminate
    case .assignment, .sharedAssignment: return .assign
    case .summary: return .summarize
    case .voteResults: return .vote
    case .pairingResult: return .choose
    case .eventInjected: return .eventInject
    case .roundStarted, .roundCompleted, .phaseStarted, .phaseCompleted,
      .agentOutput, .agentOutputStream, .relationshipUpdate,
      .conditionalEvaluated, .simulationCompleted, .roundCheckpoint,
      .simulationPaused, .error, .inferenceStarted, .inferenceCompleted,
      .languageMismatch, .turnSkipped:
      return nil
    }
  }
}
