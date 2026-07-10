import Testing

@testable import Pastura

/// ADR-022 D3 — the semantic-core mapping. Every code-phase `SimulationEvent`
/// projects to its `CodePhaseEventPayload` + fallback `PhaseType`; every
/// non-code-phase event projects to `nil` on **both** halves (the paired-nil
/// invariant the collapse in `SimulationViewModel.handleOutputEvent` relies on).
@Suite(.timeLimit(.minutes(1)))
struct CodePhaseEventPayloadEventTests {

  @Test func codePhaseEventsMapToPayload() {
    #expect(
      CodePhaseEventPayload(event: .scoreUpdate(scores: ["A": 1]))
        == .scoreUpdate(scores: ["A": 1]))
    #expect(
      CodePhaseEventPayload(event: .elimination(agent: "A", voteCount: 2))
        == .elimination(agent: "A", voteCount: 2))
    #expect(
      CodePhaseEventPayload(event: .assignment(agent: "A", value: "wolf"))
        == .assignment(agent: "A", value: "wolf"))
    #expect(
      CodePhaseEventPayload(event: .sharedAssignment(value: "topic"))
        == .sharedAssignment(value: "topic"))
    #expect(
      CodePhaseEventPayload(event: .summary(text: "s")) == .summary(text: "s"))
    #expect(
      CodePhaseEventPayload(
        event: .voteResults(votes: ["A": "B"], tallies: ["B": 1]))
        == .voteResults(votes: ["A": "B"], tallies: ["B": 1]))
    #expect(
      CodePhaseEventPayload(
        event: .pairingResult(agent1: "A", action1: "c", agent2: "B", action2: "d"))
        == .pairingResult(agent1: "A", action1: "c", agent2: "B", action2: "d"))
    #expect(
      CodePhaseEventPayload(event: .eventInjected(event: "e"))
        == .eventInjected(event: "e"))
    // Miss case (`nil`) still projects — past-results distinguishes
    // "phase didn't run" from "phase ran and rolled a miss".
    #expect(
      CodePhaseEventPayload(event: .eventInjected(event: nil))
        == .eventInjected(event: nil))
  }

  @Test func codePhaseEventsHaveFallbackPhaseType() {
    #expect(SimulationEvent.scoreUpdate(scores: [:]).defaultCodePhaseType == .scoreCalc)
    #expect(
      SimulationEvent.elimination(agent: "A", voteCount: 0).defaultCodePhaseType
        == .eliminate)
    #expect(
      SimulationEvent.assignment(agent: "A", value: "v").defaultCodePhaseType == .assign)
    #expect(SimulationEvent.sharedAssignment(value: "v").defaultCodePhaseType == .assign)
    #expect(SimulationEvent.summary(text: "s").defaultCodePhaseType == .summarize)
    #expect(
      SimulationEvent.voteResults(votes: [:], tallies: [:]).defaultCodePhaseType == .vote)
    #expect(
      SimulationEvent.pairingResult(
        agent1: "A", action1: "c", agent2: "B", action2: "d"
      ).defaultCodePhaseType == .choose)
    #expect(SimulationEvent.eventInjected(event: nil).defaultCodePhaseType == .eventInject)
  }

  @Test func nonCodePhaseEventsProjectToNilOnBothHalves() {
    let nonCodePhase: [SimulationEvent] = [
      .roundStarted(round: 1, totalRounds: 1),
      .roundCompleted(round: 1, scores: [:]),
      .phaseStarted(phaseType: .speakAll, phasePath: [0]),
      .phaseCompleted(phaseType: .speakAll, phasePath: [0]),
      .agentOutput(agent: "A", output: TurnOutput(fields: [:]), phaseType: .speakAll),
      .agentOutputStream(agent: "A", primary: nil, thought: nil),
      .relationshipUpdate(relationships: [:]),
      .conditionalEvaluated(condition: "x", result: true),
      .simulationCompleted,
      .roundCheckpoint(state: SimulationState()),
      .simulationPaused(round: 1, phasePath: [0]),
      .error(.cancelled),
      .inferenceStarted(agent: "A"),
      .inferenceCompleted(agent: "A", durationSeconds: 1, tokenCount: nil),
      .languageMismatch(agent: "A", detected: nil, expected: "ja"),
      .turnSkipped(agent: "A", phaseType: .speakAll, cause: "x")
    ]
    for event in nonCodePhase {
      #expect(CodePhaseEventPayload(event: event) == nil)
      #expect(event.defaultCodePhaseType == nil)
    }
  }
}
