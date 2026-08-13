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

  @Test func mapsRelationshipUpdate() throws {
    let line = try #require(
      EventLineMapper.map(
        .relationshipUpdate(relationships: ["A": ["B": -1], "B": ["A": 2]]),
        t: 6.0, attempt: 1))
    #expect(line.event == "relationship_update")
    #expect(line.relationships == ["A": ["B": -1], "B": ["A": 2]])
  }

  /// Pins the exact bytes of a line with **every** `EventLine` field populated.
  ///
  /// The ADR-023 Stage-4 Kotlin mirror
  /// (`shared/engine/src/commonTest/.../EventLineMapper.kt`) has to reproduce
  /// this shape, and kotlinx.serialization matches none of it by default. This
  /// test is that contract in executable form, so the mirror is written against
  /// measured bytes rather than against the two parity fixtures' observed lines
  /// — a field those fixtures never populate is exactly the one that would bite
  /// later. Four behaviours it fixes, each of which the mirror re-implements:
  ///
  /// - **Keys sort at every depth**, not just the top level (`relationships`
  ///   sorts its outer *and* inner maps).
  /// - **`nil` is omitted**, never encoded as `null`.
  /// - **`.convertToSnakeCase` leaves a trailing digit alone** — `agent2` and
  ///   `action1` stay as-is because they contain no uppercase, while
  ///   `totalRounds` becomes `total_rounds`. Measured, not derived from the
  ///   strategy's documentation.
  /// - **An integral `Double` drops its `.0`** (`t`, `duration_seconds` → `0`)
  ///   while a fractional one keeps its decimals. This is `JSONEncoder`
  ///   behaviour, and it is unrelated to the ADR-023 divergence-6 ruling on
  ///   `JSONResponseParser`'s value normalization — that one is engine
  ///   behaviour inside `fields`, this one is the transcript encoder. Do not
  ///   resolve either by pointing at the other.
  @Test func fullyPopulatedLinePinsTheWireShape() throws {
    let line = EventLine(
      t: 0, attempt: 0, event: "probe", agent: "b", round: 2, totalRounds: 4,
      scores: ["z": 1, "a": 2], phaseType: "vote", phasePath: [1, 0],
      fields: ["z": "1", "a": "2"], rawText: "raw", value: "val",
      votes: ["z": "a", "a": "z"], tallies: ["z": 1, "a": 2], agent2: "c",
      action1: "x", action2: "y", voteCount: 3, condition: "s >= 1", result: true,
      durationSeconds: 0, tokenCount: 7, detected: "en", expected: "ja",
      error: "boom", relationships: ["z": ["b": -1, "a": 1]])
    #expect(
      try JSONL.encode(line)
        == #"{"action1":"x","action2":"y","agent":"b","agent2":"c","attempt":0,"condition":"s >= 1","detected":"en","duration_seconds":0,"error":"boom","event":"probe","expected":"ja","fields":{"a":"2","z":"1"},"phase_path":[1,0],"phase_type":"vote","raw_text":"raw","relationships":{"z":{"a":1,"b":-1}},"result":true,"round":2,"scores":{"a":2,"z":1},"t":0,"tallies":{"a":2,"z":1},"token_count":7,"total_rounds":4,"type":"event","value":"val","vote_count":3,"votes":{"a":"z","z":"a"}}"#
    )

    // The integral case above is `JSONEncoder` dropping a trailing `.0`, NOT a
    // blanket integer cast — so the mirror must special-case integral doubles
    // rather than truncate. Also shows the outer map of `relationships` sorting.
    let fractional = EventLine(
      t: 1.5, attempt: 0, event: "probe", scores: ["b": 1],
      durationSeconds: 2.25, relationships: ["z": ["a": 1], "b": ["c": 2]])
    #expect(
      try JSONL.encode(fractional)
        == #"{"attempt":0,"duration_seconds":2.25,"event":"probe","relationships":{"b":{"c":2},"z":{"a":1}},"scores":{"b":1},"t":1.5,"type":"event"}"#
    )
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
      .relationshipUpdate(relationships: ["A": ["B": -1]]),
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
