import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct SimulationStateTests {
  @Test func codableRoundTrip() throws {
    let entry = ConversationEntry(
      agentName: "Alice",
      content: "I'll cooperate",
      phaseType: .speakAll,
      round: 1
    )
    let output = TurnOutput(fields: ["action": "cooperate"])

    var original = SimulationState()
    original.scores = ["Alice": 3, "Bob": 5]
    original.eliminated = ["Alice": false, "Bob": true]
    original.conversationLog = [entry]
    original.lastOutputs = ["Alice": output]
    original.voteResults = ["Alice": 2, "Bob": 1]
    original.pairings = [Pairing(agent1: "Alice", agent2: "Bob")]
    original.variables = ["assigned_topic": "Test topic"]
    original.currentRound = 2
    original.drawnEvents = ["current_event": ["retrial", "power_cut"]]

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(SimulationState.self, from: data)

    #expect(decoded.scores == original.scores)
    #expect(decoded.eliminated == original.eliminated)
    #expect(decoded.conversationLog == original.conversationLog)
    #expect(decoded.lastOutputs == original.lastOutputs)
    #expect(decoded.voteResults == original.voteResults)
    #expect(decoded.pairings == original.pairings)
    #expect(decoded.variables == original.variables)
    #expect(decoded.currentRound == original.currentRound)
    #expect(decoded.drawnEvents == original.drawnEvents)
  }

  /// Backward-compat: a `stateJSON` persisted before #1006 (no `drawnEvents`
  /// key) must still decode — a paused run resumed across the update boundary
  /// (ADR-003 / ADR-021 D8) would otherwise throw `keyNotFound` and break
  /// resume. Drives the exact unguarded path: this JSON omits `drawnEvents`,
  /// so reverting the custom `init(from:)`'s `decodeIfPresent ?? [:]` makes
  /// this test fail. `drawnEvents` decodes to empty.
  @Test func decodesLegacyStateWithoutDrawnEvents() throws {
    let legacyJSON = """
      {
        "scores": {"Alice": 1},
        "eliminated": {"Alice": false},
        "conversationLog": [],
        "lastOutputs": {},
        "voteResults": {},
        "pairings": [],
        "variables": {"current_event": "retrial"},
        "currentRound": 3
      }
      """
    let data = try #require(legacyJSON.data(using: .utf8))
    let decoded = try JSONDecoder().decode(SimulationState.self, from: data)

    #expect(decoded.drawnEvents.isEmpty)
    #expect(decoded.scores == ["Alice": 1])
    #expect(decoded.currentRound == 3)
    #expect(decoded.variables == ["current_event": "retrial"])
  }

  @Test func initialStateFromScenario() {
    let scenario = Scenario(
      id: "test",
      name: "Test",
      description: "A test scenario",
      language: "ja",
      agentCount: 2,
      rounds: 3,
      context: "Test context",
      personas: [
        Persona(name: "Alice", description: "Persona A"),
        Persona(name: "Bob", description: "Persona B")
      ],
      phases: []
    )

    let state = SimulationState.initial(for: scenario)

    #expect(state.scores == ["Alice": 0, "Bob": 0])
    #expect(state.eliminated == ["Alice": false, "Bob": false])
    #expect(state.conversationLog.isEmpty)
    #expect(state.lastOutputs.isEmpty)
    #expect(state.currentRound == 0)
  }

  @Test func defaultInitializerCreatesEmptyState() {
    let state = SimulationState()

    #expect(state.scores.isEmpty)
    #expect(state.eliminated.isEmpty)
    #expect(state.conversationLog.isEmpty)
    #expect(state.lastOutputs.isEmpty)
    #expect(state.voteResults.isEmpty)
    #expect(state.pairings.isEmpty)
    #expect(state.variables.isEmpty)
    #expect(state.currentRound == 0)
    #expect(state.drawnEvents.isEmpty)
  }
}
