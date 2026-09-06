import Foundation
import PasturaSharedEngine

// `SimulationEvent` (and `SimulationError`, `PhaseType`, `SimulationState`,
// `TurnOutput`, `ConversationEntry`, `Pairing`) are among the Kotlin types
// with a Swift twin in this module, so every Kotlin spelling below is
// qualified `PasturaSharedEngine.X` — a bare name binds to the Swift twin
// (`.claude/rules/kmp-interop.md` Pattern 1b). No typealias: an alias would
// hide the shadowing from the next reader.

/// Converts a Kotlin `SimulationEvent` (one of the 26 exported subclasses)
/// into the Swift ``SimulationEvent`` the App layer — most directly
/// `SimulationViewModel` — already knows how to consume.
///
/// **Why this exists.** ADR-023 §5.1 puts the K/N boundary adapters under
/// `App/KMP/` (§6 ruling (c)): the Engine and App layers keep talking through
/// the unchanged Swift `SimulationEvent` surface, and this file is what
/// lets a Kotlin-engine run pretend, from the ViewModel's point of view, to
/// be just another `AsyncStream<SimulationEvent>`.
///
/// **Why the initializer is failable.** A Kotlin sealed class is not
/// switch-exhaustive from Swift — K/N exports it as an Obj-C class
/// hierarchy, so this can only be an `as?` chain, and the compiler cannot
/// tell us when Kotlin gains a 27th subclass. Returning `nil` for an
/// unrecognised subclass — rather than `fatalError` — means a Kotlin bump
/// that adds a case cannot crash a shipped app: the caller (the S5-4/S5-5
/// runner reading the Kotlin event stream) logs and drops the event instead.
extension SimulationEvent {

  /// Builds the Swift event from its Kotlin counterpart, or `nil` if
  /// `shared` is a subclass this build predates (see the type-level doc).
  /// Every `nil` path in this file is unreachable from Swift today — an
  /// unknown subclass, error subclass or enum constant cannot be synthesized
  /// against the exported header — so they are untested; the green suite
  /// covers the mapping, not the fallback.
  ///
  /// Split into six per-category mappers (round/phase lifecycle, agent
  /// output, code-phase results, vote/pairing/control-flow, simulation
  /// lifecycle, progress/degradation) purely to stay under SwiftLint's
  /// cyclomatic-complexity and function-length caps for a single 26-case
  /// `as?` chain — each mapper returning `nil` (whether because `shared` is
  /// a different subclass, or because a matched subclass's nested
  /// `PhaseType` didn't map) simply falls through to the next, and the
  /// category split carries no semantic meaning of its own.
  nonisolated init?(shared: PasturaSharedEngine.SimulationEvent) {
    if let event = Self.mapRoundAndPhaseLifecycle(shared) {
      self = event
    } else if let event = Self.mapAgentOutput(shared) {
      self = event
    } else if let event = Self.mapCodePhaseResults(shared) {
      self = event
    } else if let event = Self.mapVoteAndControlFlow(shared) {
      self = event
    } else if let event = Self.mapSimulationLifecycle(shared) {
      self = event
    } else if let event = Self.mapProgressAndDegradation(shared) {
      self = event
    } else {
      // An unrecognised subclass means Kotlin added a 27th case this build
      // predates. Return nil rather than crash — the caller logs and drops.
      return nil
    }
  }

  nonisolated private static func mapRoundAndPhaseLifecycle(
    _ shared: PasturaSharedEngine.SimulationEvent
  ) -> SimulationEvent? {
    if let event = shared as? PasturaSharedEngine.SimulationEvent.RoundStarted {
      return .roundStarted(round: Int(event.round), totalRounds: Int(event.totalRounds))
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.RoundCompleted {
      return .roundCompleted(
        round: Int(event.round), scores: event.scores.mapValues { Int(truncating: $0) })
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.PhaseStarted {
      guard let phaseType = PhaseType(shared: event.phaseType) else { return nil }
      return .phaseStarted(
        phaseType: phaseType, phasePath: event.phasePath.map { Int(truncating: $0) })
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.PhaseCompleted {
      guard let phaseType = PhaseType(shared: event.phaseType) else { return nil }
      return .phaseCompleted(
        phaseType: phaseType, phasePath: event.phasePath.map { Int(truncating: $0) })
    }
    return nil
  }

  nonisolated private static func mapAgentOutput(
    _ shared: PasturaSharedEngine.SimulationEvent
  ) -> SimulationEvent? {
    if let event = shared as? PasturaSharedEngine.SimulationEvent.AgentOutput {
      guard let phaseType = PhaseType(shared: event.phaseType) else { return nil }
      return .agentOutput(
        agent: event.agent, output: TurnOutput(shared: event.output), phaseType: phaseType)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.AgentOutputStream {
      return .agentOutputStream(agent: event.agent, primary: event.primary, thought: event.thought)
    }
    return nil
  }

  nonisolated private static func mapCodePhaseResults(
    _ shared: PasturaSharedEngine.SimulationEvent
  ) -> SimulationEvent? {
    if let event = shared as? PasturaSharedEngine.SimulationEvent.ScoreUpdate {
      return .scoreUpdate(scores: event.scores.mapValues { Int(truncating: $0) })
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.Elimination {
      return .elimination(agent: event.agent, voteCount: Int(event.voteCount))
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.Assignment {
      return .assignment(agent: event.agent, value: event.value)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.SharedAssignment {
      return .sharedAssignment(value: event.value)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.Summary {
      return .summary(text: event.text)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.Narration {
      return .narration(text: event.text)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.RelationshipUpdate {
      return .relationshipUpdate(
        relationships: event.relationships.mapValues { row in
          row.mapValues { Int(truncating: $0) }
        })
    }
    return nil
  }

  nonisolated private static func mapVoteAndControlFlow(
    _ shared: PasturaSharedEngine.SimulationEvent
  ) -> SimulationEvent? {
    if let event = shared as? PasturaSharedEngine.SimulationEvent.VoteResults {
      return .voteResults(
        votes: event.votes, tallies: event.tallies.mapValues { Int(truncating: $0) })
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.PairingResult {
      return .pairingResult(
        agent1: event.agent1, action1: event.action1, agent2: event.agent2,
        action2: event.action2)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.ConditionalEvaluated {
      return .conditionalEvaluated(condition: event.condition, result: event.result)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.EventInjected {
      return .eventInjected(event: event.event)
    }
    return nil
  }

  nonisolated private static func mapSimulationLifecycle(
    _ shared: PasturaSharedEngine.SimulationEvent
  ) -> SimulationEvent? {
    if shared is PasturaSharedEngine.SimulationEvent.SimulationCompleted {
      return .simulationCompleted
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.RoundCheckpoint {
      guard let state = SimulationState(shared: event.state) else { return nil }
      return .roundCheckpoint(state: state)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.SimulationPaused {
      return .simulationPaused(
        round: Int(event.round), phasePath: event.phasePath.map { Int(truncating: $0) })
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.ErrorEvent {
      guard let error = SimulationError(shared: event.error) else { return nil }
      return .error(error)
    }
    return nil
  }

  nonisolated private static func mapProgressAndDegradation(
    _ shared: PasturaSharedEngine.SimulationEvent
  ) -> SimulationEvent? {
    if let event = shared as? PasturaSharedEngine.SimulationEvent.InferenceStarted {
      return .inferenceStarted(agent: event.agent)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.InferenceCompleted {
      return .inferenceCompleted(
        agent: event.agent, durationSeconds: event.durationSeconds,
        tokenCount: event.tokenCount.map { Int(truncating: $0) })
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.LanguageMismatch {
      return .languageMismatch(
        agent: event.agent, detected: event.detected, expected: event.expected)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.TurnSkipped {
      guard let phaseType = PhaseType(shared: event.phaseType) else { return nil }
      return .turnSkipped(agent: event.agent, phaseType: phaseType, cause: event.cause)
    } else if let event = shared as? PasturaSharedEngine.SimulationEvent.ActionRejected {
      guard let phaseType = PhaseType(shared: event.phaseType) else { return nil }
      return .actionRejected(agent: event.agent, phaseType: phaseType, raw: event.raw)
    }
    return nil
  }
}

extension PhaseType {
  /// Maps a Kotlin `PhaseType` enum constant by its `name` (K/N's
  /// `SPEAK_ALL` / `VOTE` / … form), lowercased to match the Swift raw
  /// values (`speak_all`, `vote`, …). That coincides with each entry's
  /// `@SerialName` today, and `@SerialName` is the authoritative spelling —
  /// `SimulationEventBridgeTests.phaseTypeRosterMapsCompletely` is the
  /// detector for an entry whose serial name diverges. Failable so an enum
  /// constant this build predates degrades to "unknown event" at the call
  /// site rather than trapping.
  nonisolated init?(shared: PasturaSharedEngine.PhaseType) {
    self.init(rawValue: shared.name.lowercased())
  }
}

extension TurnOutput {
  /// Kotlin's `TurnOutput` stores only `fields` (its `statement` / `vote` /
  /// `action` / `reason` / `innerThought` are computed over it) — `rawText`
  /// is parser provenance the Kotlin port omits — so `rawText` is always
  /// `nil` here. The ViewModel DOES read it: it is the `TurnRecord.rawOutput`
  /// audit column (ADR-015), which is therefore empty for every Kotlin-engine
  /// turn; `SimulationViewModel` suppresses its "wiring broken" log on this
  /// path, and S5-5 settles whether to port the field or drop the column
  /// (ADR-023 §6 S5-4, #501).
  nonisolated init(shared: PasturaSharedEngine.TurnOutput) {
    self.init(fields: shared.fields, rawText: nil)
  }
}

extension ConversationEntry {
  /// Failable because `phaseType` routes through ``PhaseType/init(shared:)``.
  nonisolated init?(shared: PasturaSharedEngine.ConversationEntry) {
    guard let phaseType = PhaseType(shared: shared.phaseType) else { return nil }
    self.init(
      agentName: shared.agentName, content: shared.content, phaseType: phaseType,
      round: Int(shared.round))
  }
}

extension Pairing {
  /// Total — every Kotlin field maps 1:1, both actions nullable on both sides.
  nonisolated init(shared: PasturaSharedEngine.Pairing) {
    self.init(
      agent1: shared.agent1, agent2: shared.agent2, action1: shared.action1,
      action2: shared.action2)
  }
}

extension SimulationState {
  /// Failable because `conversationLog` entries route through
  /// ``ConversationEntry/init(shared:)``, which is itself failable via
  /// `PhaseType`. An entry this build cannot map fails the whole state
  /// conversion rather than silently dropping conversation history —
  /// `.roundCheckpoint`'s caller (pause/resume persistence) needs the state
  /// it stores to be complete, not a best-effort subset. Blast radius of the
  /// drop: the runner logs it at `.error` and the previous round's checkpoint
  /// stays the persisted one, so a later resume replays a round rather than
  /// failing loudly — unreachable from Swift today (no unknown `PhaseType`
  /// can be built), hence untested.
  nonisolated init?(shared: PasturaSharedEngine.SimulationState) {
    var conversationLog: [ConversationEntry] = []
    conversationLog.reserveCapacity(shared.conversationLog.count)
    for entry in shared.conversationLog {
      guard let converted = ConversationEntry(shared: entry) else { return nil }
      conversationLog.append(converted)
    }
    self.init(
      scores: shared.scores.mapValues { Int(truncating: $0) },
      eliminated: shared.eliminated.mapValues(\.boolValue),
      conversationLog: conversationLog,
      lastOutputs: shared.lastOutputs.mapValues(TurnOutput.init(shared:)),
      voteResults: shared.voteResults.mapValues { Int(truncating: $0) },
      pairings: shared.pairings.map(Pairing.init(shared:)),
      variables: shared.variables,
      currentRound: Int(shared.currentRound),
      drawnEvents: shared.drawnEvents)
  }
}

extension SimulationError {
  /// A Kotlin sealed class is not switch-exhaustive from Swift, so this is
  /// an `as?` chain like ``SimulationEvent/init(shared:)`` — same failure
  /// mode, same remedy: an unrecognised subclass returns `nil` rather than
  /// trapping, and ``SimulationEvent/init(shared:)`` propagates that `nil`
  /// for its `.error` case.
  nonisolated init?(shared: PasturaSharedEngine.SimulationError) {
    if shared is PasturaSharedEngine.SimulationError.Cancelled {
      self = .cancelled
    } else if let error = shared as? PasturaSharedEngine.SimulationError.JsonParseFailed {
      self = .jsonParseFailed(raw: error.raw)
    } else if let error = shared as? PasturaSharedEngine.SimulationError.LlmGenerationFailed {
      // `description` collides with `NSObject.description()`, so K/N exports
      // the property as `description_`.
      self = .llmGenerationFailed(description: error.description_)
    } else if shared is PasturaSharedEngine.SimulationError.ModelNotLoaded {
      self = .modelNotLoaded
    } else if shared is PasturaSharedEngine.SimulationError.RetriesExhausted {
      self = .retriesExhausted
    } else if let error = shared as? PasturaSharedEngine.SimulationError.ScenarioValidationFailed {
      self = .scenarioValidationFailed(error.message)
    } else if let error = shared as? PasturaSharedEngine.SimulationError.TurnFailureLimitReached {
      self = .turnFailureLimitReached(consecutiveCount: Int(error.consecutiveCount))
    } else {
      return nil
    }
  }
}
