import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

@Suite(.timeLimit(.minutes(1)))
struct RunLogTests {
  @Test func encodesSingleSortedSnakeCaseLine() throws {
    let line = EventLine(
      t: 1.5, attempt: 1, event: "round_started", round: 1, totalRounds: 3)
    let json = try JSONL.encode(line)
    #expect(!json.contains("\n"))
    #expect(json.contains("\"event\":\"round_started\""))
    #expect(json.contains("\"total_rounds\":3"))
    // nil payload fields are omitted, not encoded as null
    #expect(!json.contains("null"))
  }

  @Test func runStartAndEndLinesRoundTrip() throws {
    let start = RunStartLine(
      runId: "20260613-010000-abcd", date: "2026-06-13T01:00:00Z",
      scenarioId: "prisoners_dilemma", scenarioName: "囚人のジレンマ",
      language: "ja", model: "Gemma 4 E2B (Q4_K_M)", timeoutSec: 1800,
      estimatedInferences: 45)
    let startJSON = try JSONL.encode(start)
    #expect(startJSON.contains("\"type\":\"run_start\""))
    #expect(startJSON.contains("\"estimated_inferences\":45"))

    let end = RunEndLine(
      runId: "20260613-010000-abcd", status: .error, attempts: 2,
      durationSec: 12.25, error: "timeout after 1800s")
    let endJSON = try JSONL.encode(end)
    #expect(endJSON.contains("\"type\":\"run_end\""))
    #expect(endJSON.contains("\"status\":\"error\""))
    #expect(endJSON.contains("\"attempts\":2"))
  }

  @Test func mapsAgentOutputWithFieldsAndRawText() throws {
    let event = SimulationEvent.agentOutput(
      agent: "アキラ",
      output: TurnOutput(fields: ["statement": "協力する"], rawText: "{\"statement\": \"協力する\"}"),
      phaseType: .speakAll)
    let line = try #require(EventLineMapper.map(event, t: 2.0, attempt: 1))
    #expect(line.event == "agent_output")
    #expect(line.agent == "アキラ")
    #expect(line.phaseType == "speak_all")
    #expect(line.fields == ["statement": "協力する"])
    #expect(line.rawText == "{\"statement\": \"協力する\"}")
  }

  @Test func skipsStreamingDeltas() {
    let event = SimulationEvent.agentOutputStream(
      agent: "アキラ", primary: "協", thought: nil)
    #expect(EventLineMapper.map(event, t: 0.1, attempt: 1) == nil)
  }

  @Test func mapsErrorWithDescription() throws {
    let event = SimulationEvent.error(.retriesExhausted)
    let line = try #require(EventLineMapper.map(event, t: 3.0, attempt: 2))
    #expect(line.event == "error")
    #expect(line.attempt == 2)
    #expect(line.error?.isEmpty == false)
  }

  @Test func mapsScoresAndVotes() throws {
    let scores = try #require(
      EventLineMapper.map(
        .roundCompleted(round: 2, scores: ["A": 3, "B": 5]), t: 4.0, attempt: 1))
    #expect(scores.event == "round_completed")
    #expect(scores.scores == ["A": 3, "B": 5])

    let votes = try #require(
      EventLineMapper.map(
        .voteResults(votes: ["A": "B"], tallies: ["B": 1]), t: 5.0, attempt: 1))
    #expect(votes.event == "vote_results")
    #expect(votes.votes == ["A": "B"])
    #expect(votes.tallies == ["B": 1])
  }

  @Test func everyEventKindExceptStreamAndCheckpointProducesALine() {
    // Completeness canary: if SimulationEvent gains a case, the mapper's
    // switch breaks compilation; this test documents the two deliberate nils
    // (`.agentOutputStream` and `.roundCheckpoint`, asserted below).
    let mapped: [SimulationEvent] = [
      .roundStarted(round: 1, totalRounds: 1),
      .roundCompleted(round: 1, scores: ["A": 1]),
      .agentOutput(agent: "A", output: TurnOutput(fields: [:]), phaseType: .vote),
      .voteResults(votes: ["A": "B"], tallies: ["B": 1]),
      .error(.cancelled),
      .phaseStarted(phaseType: .vote, phasePath: [0]),
      .phaseCompleted(phaseType: .vote, phasePath: [0]),
      .scoreUpdate(scores: [:]),
      .elimination(agent: "A", voteCount: 2),
      .assignment(agent: "A", value: "wolf"),
      .summary(text: "round over"),
      .pairingResult(agent1: "A", action1: "c", agent2: "B", action2: "d"),
      .conditionalEvaluated(condition: "max_score >= 10", result: false),
      .eventInjected(event: "storm"),
      .simulationCompleted,
      .simulationPaused(round: 1, phasePath: [0]),
      .inferenceStarted(agent: "A"),
      .inferenceCompleted(agent: "A", durationSeconds: 1.0, tokenCount: 42),
      .languageMismatch(agent: "A", detected: "en", expected: "ja")
    ]
    for event in mapped {
      #expect(EventLineMapper.map(event, t: 0, attempt: 1) != nil)
    }

    // The two deliberate exceptions produce no transcript line.
    #expect(
      EventLineMapper.map(
        .agentOutputStream(agent: "A", primary: "hi", thought: nil), t: 0, attempt: 1) == nil)
    #expect(
      EventLineMapper.map(.roundCheckpoint(state: SimulationState()), t: 0, attempt: 1) == nil)
  }
}
