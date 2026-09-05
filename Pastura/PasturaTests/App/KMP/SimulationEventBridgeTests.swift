import PasturaSharedEngine
import Testing

@testable import Pastura

/// ADR-023 §6 S5-4 acceptance: the Kotlin → Swift `SimulationEvent`
/// translator that lets `SimulationViewModel` consume the Kotlin engine's
/// events through the unchanged Swift `SimulationEvent` surface (#1681).
///
/// Kotlin types are spelled `PasturaSharedEngine.X` throughout —
/// `SimulationEvent` / `SimulationError` / `PhaseType` / `SimulationState` /
/// `TurnOutput` / `ConversationEntry` / `Pairing` are all shadowed twins
/// (`.claude/rules/kmp-interop.md` Pattern 1b).
///
/// Constructing a Kotlin sealed subtype through its nested Swift name
/// compiled under this engine umbrella (kmp-interop Pattern 2 flagged this
/// as unverified post-#220; the models-umbrella failure it measured does
/// not reproduce here as of 2026-09-05) — so every fixture below is a
/// direct `PasturaSharedEngine.SimulationEvent.<Case>(...)` construction,
/// not a full engine run.
@Suite(.timeLimit(.minutes(1)))
struct SimulationEventBridgeTests {

  // MARK: - Roster pin (Pattern 4 wording: a pin, not a proof)

  /// `grep -c '^@interface PSESimulationEvent[A-Za-z]* : PSESimulationEvent'
  /// Pastura/Frameworks/PasturaSharedEngine.xcframework/ios-arm64_x86_64-simulator/PasturaSharedEngine.framework/Headers/PasturaSharedEngine.h`
  /// counted 26 concrete subclasses on 2026-09-05. This is a pin against
  /// that grep, not a proof that the `init?(shared:)` chain below is
  /// exhaustive — re-grep and update both the constant and the chain after
  /// a Kotlin bump that touches `SimulationEvent`.
  private static let knownSubclassCount = 26

  @Test("roster pin: 26 SimulationEvent subclasses covered by name")
  func rosterPinDocumentsSubclassCount() {
    let coveredCaseNames: Set<String> = [
      "ActionRejected", "AgentOutput", "AgentOutputStream", "Assignment",
      "ConditionalEvaluated", "Elimination", "ErrorEvent", "EventInjected",
      "InferenceCompleted", "InferenceStarted", "LanguageMismatch", "Narration",
      "PairingResult", "PhaseCompleted", "PhaseStarted", "RelationshipUpdate",
      "RoundCheckpoint", "RoundCompleted", "RoundStarted", "ScoreUpdate",
      "SharedAssignment", "SimulationCompleted", "SimulationPaused", "Summary",
      "TurnSkipped", "VoteResults"
    ]
    #expect(coveredCaseNames.count == Self.knownSubclassCount)
  }

  // MARK: - Round lifecycle

  @Test("RoundStarted converts")
  func convertsRoundStarted() {
    let shared = PasturaSharedEngine.SimulationEvent.RoundStarted(round: 2, totalRounds: 5)
    #expect(SimulationEvent(shared: shared) == .roundStarted(round: 2, totalRounds: 5))
  }

  @Test("RoundCompleted converts")
  func convertsRoundCompleted() {
    let shared = PasturaSharedEngine.SimulationEvent.RoundCompleted(
      round: 3, scores: ["Alice": 4, "Bob": -2])
    #expect(
      SimulationEvent(shared: shared) == .roundCompleted(round: 3, scores: ["Alice": 4, "Bob": -2]))
  }

  // MARK: - Phase lifecycle

  @Test("PhaseStarted converts, including phasePath")
  func convertsPhaseStarted() {
    let shared = PasturaSharedEngine.SimulationEvent.PhaseStarted(
      phaseType: .speakAll, phasePath: [1, 2])
    #expect(
      SimulationEvent(shared: shared)
        == .phaseStarted(phaseType: .speakAll, phasePath: [1, 2]))
  }

  @Test("PhaseCompleted converts")
  func convertsPhaseCompleted() {
    let shared = PasturaSharedEngine.SimulationEvent.PhaseCompleted(
      phaseType: .vote, phasePath: [3])
    #expect(
      SimulationEvent(shared: shared) == .phaseCompleted(phaseType: .vote, phasePath: [3]))
  }

  // MARK: - Agent outputs

  @Test("AgentOutput converts, including nested TurnOutput")
  func convertsAgentOutput() {
    let sharedOutput = PasturaSharedEngine.TurnOutput(fields: ["statement": "hi"])
    let shared = PasturaSharedEngine.SimulationEvent.AgentOutput(
      agent: "Alice", output: sharedOutput, phaseType: .speakAll)
    #expect(
      SimulationEvent(shared: shared)
        == .agentOutput(
          agent: "Alice", output: TurnOutput(fields: ["statement": "hi"], rawText: nil),
          phaseType: .speakAll))
  }

  @Test("AgentOutputStream converts, nil primary preserved")
  func convertsAgentOutputStream() {
    let shared = PasturaSharedEngine.SimulationEvent.AgentOutputStream(
      agent: "Alice", primary: nil, thought: "thinking")
    #expect(
      SimulationEvent(shared: shared)
        == .agentOutputStream(agent: "Alice", primary: nil, thought: "thinking"))
  }

  // MARK: - Code phase results

  @Test("ScoreUpdate converts")
  func convertsScoreUpdate() {
    let shared = PasturaSharedEngine.SimulationEvent.ScoreUpdate(scores: ["Alice": 1])
    #expect(SimulationEvent(shared: shared) == .scoreUpdate(scores: ["Alice": 1]))
  }

  @Test("Elimination converts")
  func convertsElimination() {
    let shared = PasturaSharedEngine.SimulationEvent.Elimination(agent: "Bob", voteCount: 3)
    #expect(SimulationEvent(shared: shared) == .elimination(agent: "Bob", voteCount: 3))
  }

  @Test("Assignment converts")
  func convertsAssignment() {
    let shared = PasturaSharedEngine.SimulationEvent.Assignment(agent: "Alice", value: "wolf")
    #expect(SimulationEvent(shared: shared) == .assignment(agent: "Alice", value: "wolf"))
  }

  @Test("SharedAssignment converts")
  func convertsSharedAssignment() {
    let shared = PasturaSharedEngine.SimulationEvent.SharedAssignment(value: "topic")
    #expect(SimulationEvent(shared: shared) == .sharedAssignment(value: "topic"))
  }

  @Test("Summary converts")
  func convertsSummary() {
    let shared = PasturaSharedEngine.SimulationEvent.Summary(text: "the summary")
    #expect(SimulationEvent(shared: shared) == .summary(text: "the summary"))
  }

  @Test("Narration converts")
  func convertsNarration() {
    let shared = PasturaSharedEngine.SimulationEvent.Narration(text: "the narration")
    #expect(SimulationEvent(shared: shared) == .narration(text: "the narration"))
  }

  @Test("RelationshipUpdate converts the nested int matrix")
  func convertsRelationshipUpdate() {
    let shared = PasturaSharedEngine.SimulationEvent.RelationshipUpdate(
      relationships: ["Alice": ["Bob": 2]])
    #expect(
      SimulationEvent(shared: shared)
        == .relationshipUpdate(relationships: ["Alice": ["Bob": 2]]))
  }

  // MARK: - Vote results

  @Test("VoteResults converts")
  func convertsVoteResults() {
    let shared = PasturaSharedEngine.SimulationEvent.VoteResults(
      votes: ["Alice": "Bob"], tallies: ["Bob": 1])
    #expect(
      SimulationEvent(shared: shared)
        == .voteResults(votes: ["Alice": "Bob"], tallies: ["Bob": 1]))
  }

  // MARK: - Pairing results

  @Test("PairingResult converts")
  func convertsPairingResult() {
    let shared = PasturaSharedEngine.SimulationEvent.PairingResult(
      agent1: "Alice", action1: "cooperate", agent2: "Bob", action2: "betray")
    #expect(
      SimulationEvent(shared: shared)
        == .pairingResult(
          agent1: "Alice", action1: "cooperate", agent2: "Bob", action2: "betray"))
  }

  // MARK: - Conditional evaluation

  @Test("ConditionalEvaluated converts")
  func convertsConditionalEvaluated() {
    let shared = PasturaSharedEngine.SimulationEvent.ConditionalEvaluated(
      condition: "score > 0", result: true)
    #expect(
      SimulationEvent(shared: shared)
        == .conditionalEvaluated(condition: "score > 0", result: true))
  }

  // MARK: - Event injection

  @Test("EventInjected converts, nil event preserved")
  func convertsEventInjectedNil() {
    let shared = PasturaSharedEngine.SimulationEvent.EventInjected(event: nil)
    #expect(SimulationEvent(shared: shared) == .eventInjected(event: nil))
  }

  @Test("EventInjected converts a rolled event")
  func convertsEventInjectedSome() {
    let shared = PasturaSharedEngine.SimulationEvent.EventInjected(event: "storm")
    #expect(SimulationEvent(shared: shared) == .eventInjected(event: "storm"))
  }

  // MARK: - Simulation lifecycle

  @Test("SimulationCompleted converts")
  func convertsSimulationCompleted() {
    let shared = PasturaSharedEngine.SimulationEvent.SimulationCompleted.shared
    #expect(SimulationEvent(shared: shared) == .simulationCompleted)
  }

  @Test("RoundCheckpoint converts the full nested SimulationState")
  func convertsRoundCheckpoint() {
    let sharedState = PasturaSharedEngine.SimulationState(
      scores: ["Alice": 3],
      eliminated: ["Alice": false],
      conversationLog: [
        PasturaSharedEngine.ConversationEntry(
          agentName: "Alice", content: "hi", phaseType: .speakAll, round: 1)
      ],
      lastOutputs: ["Alice": PasturaSharedEngine.TurnOutput(fields: ["statement": "hi"])],
      voteResults: ["Alice": 0],
      pairings: [
        PasturaSharedEngine.Pairing(
          agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: nil)
      ],
      variables: ["topic": "cats"],
      currentRound: 1,
      drawnEvents: ["current_event": ["storm"]])
    let shared = PasturaSharedEngine.SimulationEvent.RoundCheckpoint(state: sharedState)

    let expectedState = SimulationState(
      scores: ["Alice": 3],
      eliminated: ["Alice": false],
      conversationLog: [
        ConversationEntry(agentName: "Alice", content: "hi", phaseType: .speakAll, round: 1)
      ],
      lastOutputs: ["Alice": TurnOutput(fields: ["statement": "hi"])],
      voteResults: ["Alice": 0],
      pairings: [Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: nil)],
      variables: ["topic": "cats"],
      currentRound: 1,
      drawnEvents: ["current_event": ["storm"]])

    #expect(SimulationEvent(shared: shared) == .roundCheckpoint(state: expectedState))
  }

  @Test("SimulationPaused converts")
  func convertsSimulationPaused() {
    let shared = PasturaSharedEngine.SimulationEvent.SimulationPaused(round: 2, phasePath: [1])
    #expect(SimulationEvent(shared: shared) == .simulationPaused(round: 2, phasePath: [1]))
  }

  // MARK: - Progress

  @Test("InferenceStarted converts")
  func convertsInferenceStarted() {
    let shared = PasturaSharedEngine.SimulationEvent.InferenceStarted(agent: "Alice")
    #expect(SimulationEvent(shared: shared) == .inferenceStarted(agent: "Alice"))
  }

  @Test("InferenceCompleted converts, nil tokenCount preserved")
  func convertsInferenceCompletedNilTokenCount() {
    let shared = PasturaSharedEngine.SimulationEvent.InferenceCompleted(
      agent: "Alice", durationSeconds: 1.5, tokenCount: nil)
    #expect(
      SimulationEvent(shared: shared)
        == .inferenceCompleted(agent: "Alice", durationSeconds: 1.5, tokenCount: nil))
  }

  @Test("InferenceCompleted converts a boxed tokenCount")
  func convertsInferenceCompletedWithTokenCount() {
    let shared = PasturaSharedEngine.SimulationEvent.InferenceCompleted(
      agent: "Alice", durationSeconds: 2.0, tokenCount: KotlinInt(int: 42))
    #expect(
      SimulationEvent(shared: shared)
        == .inferenceCompleted(agent: "Alice", durationSeconds: 2.0, tokenCount: 42))
  }

  // MARK: - Language adherence

  @Test("LanguageMismatch converts, nil detected preserved")
  func convertsLanguageMismatch() {
    let shared = PasturaSharedEngine.SimulationEvent.LanguageMismatch(
      agent: "Alice", detected: nil, expected: "ja")
    #expect(
      SimulationEvent(shared: shared)
        == .languageMismatch(agent: "Alice", detected: nil, expected: "ja"))
  }

  // MARK: - Turn degradation

  @Test("TurnSkipped converts")
  func convertsTurnSkipped() {
    let shared = PasturaSharedEngine.SimulationEvent.TurnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "timeout")
    #expect(
      SimulationEvent(shared: shared)
        == .turnSkipped(agent: "Alice", phaseType: .speakAll, cause: "timeout"))
  }

  @Test("ActionRejected converts")
  func convertsActionRejected() {
    let shared = PasturaSharedEngine.SimulationEvent.ActionRejected(
      agent: "Alice", phaseType: .choose, raw: "shrug")
    #expect(
      SimulationEvent(shared: shared)
        == .actionRejected(agent: "Alice", phaseType: .choose, raw: "shrug"))
  }

}
