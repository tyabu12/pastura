import Foundation
import Testing

@testable import Pastura

/// End-to-end test exercising the full Data layer workflow
/// as the App layer would use it.
@Suite struct DataIntegrationTests {

  private struct Repos {
    let manager: DatabaseManager
    let scenario: GRDBScenarioRepository
    let simulation: GRDBSimulationRepository
    let turn: GRDBTurnRepository
  }

  private func makeRepos() throws -> Repos {
    let manager = try DatabaseManager.inMemory()
    return Repos(
      manager: manager,
      scenario: GRDBScenarioRepository(dbWriter: manager.dbWriter),
      simulation: GRDBSimulationRepository(dbWriter: manager.dbWriter),
      turn: GRDBTurnRepository(dbWriter: manager.dbWriter))
  }

  // swiftlint:disable:next function_body_length
  @Test func fullSimulationWorkflow() throws {
    let repos = try makeRepos()

    // 1. Save a scenario
    let scenarioRecord = ScenarioRecord(
      id: "s1", name: "Prisoner's Dilemma",
      yamlDefinition: "name: Prisoner's Dilemma\nrounds: 3",
      isPreset: true, createdAt: Date(), updatedAt: Date())
    try repos.scenario.save(scenarioRecord)

    // 2. Create a simulation linked to that scenario
    let initialState = SimulationState.initial(
      for: Scenario(
        id: "s1", name: "Prisoner's Dilemma",
        description: "Classic game theory scenario",
        agentCount: 2, rounds: 3, context: "You are playing...",
        personas: [
          Persona(name: "Alice", description: "Cooperative"),
          Persona(name: "Bob", description: "Competitive")
        ],
        phases: [], extraData: [:]))
    let stateJSON = try JSONEncoder().encode(initialState)
    let stateJSONString = String(data: stateJSON, encoding: .utf8)!

    let simRecord = SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: SimulationStatus.running.rawValue,
      currentRound: 0, currentPhaseIndex: 0,
      stateJSON: stateJSONString, configJSON: nil,
      createdAt: Date(), updatedAt: Date())
    try repos.simulation.save(simRecord)

    // 3. Save turn records (simulating agent outputs)
    let turns = [
      TurnRecord(
        id: "t1", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Alice",
        rawOutput: #"{"statement": "I will cooperate"}"#,
        parsedOutputJSON: #"{"statement":"I will cooperate"}"#,
        createdAt: Date()),
      TurnRecord(
        id: "t2", simulationId: "sim1",
        roundNumber: 1, phaseType: "speak_all",
        agentName: "Bob",
        rawOutput: #"{"statement": "I choose to betray"}"#,
        parsedOutputJSON: #"{"statement":"I choose to betray"}"#,
        createdAt: Date())
    ]
    try repos.turn.saveBatch(turns)

    // 4. Update simulation state (pause)
    var updatedState = initialState
    updatedState.scores = ["Alice": 0, "Bob": 5]
    updatedState.currentRound = 1
    let updatedJSON = try JSONEncoder().encode(updatedState)
    let updatedJSONString = String(data: updatedJSON, encoding: .utf8)!

    try repos.simulation.updateState(
      "sim1", stateJSON: updatedJSONString,
      currentRound: 1, currentPhaseIndex: 0)
    try repos.simulation.updateStatus("sim1", status: .paused)

    // 5. Verify paused simulation state
    let pausedSim = try repos.simulation.fetchById("sim1")
    #expect(pausedSim?.simulationStatus == .paused)
    #expect(pausedSim?.currentRound == 1)

    // 6. Decode stateJSON back to SimulationState
    let decodedState = try JSONDecoder().decode(
      SimulationState.self,
      from: Data(pausedSim!.stateJSON.utf8))
    #expect(decodedState.scores["Alice"] == 0)
    #expect(decodedState.scores["Bob"] == 5)
    #expect(decodedState.currentRound == 1)

    // 7. Fetch turns by round
    let round1Turns = try repos.turn.fetchBySimulationAndRound("sim1", round: 1)
    #expect(round1Turns.count == 2)

    // 8. Delete scenario — cascade removes simulation and turns
    try repos.scenario.delete("s1")
    let deletedSim = try repos.simulation.fetchById("sim1")
    #expect(deletedSim == nil)
    let remainingTurns = try repos.turn.fetchBySimulationId("sim1")
    #expect(remainingTurns.isEmpty)
  }

  @Test func simulationStateJsonRoundTrip() throws {
    let repos = try makeRepos()

    // Create a rich SimulationState
    let state = SimulationState(
      scores: ["Alice": 10, "Bob": 7, "Charlie": 3],
      eliminated: ["Alice": false, "Bob": false, "Charlie": true],
      conversationLog: [
        ConversationEntry(
          agentName: "Alice", content: "Hello everyone",
          phaseType: .speakAll, round: 1)
      ],
      lastOutputs: [
        "Alice": TurnOutput(fields: ["statement": "Hello everyone"])
      ],
      voteResults: ["Alice": 2, "Bob": 1],
      pairings: [
        Pairing(
          agent1: "Alice", agent2: "Bob",
          action1: "cooperate", action2: "betray")
      ],
      variables: ["topic": "weather"],
      currentRound: 3)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let stateJSON = String(data: try encoder.encode(state), encoding: .utf8)!

    // Save scenario + simulation
    try repos.scenario.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))
    try repos.simulation.save(
      SimulationRecord(
        id: "sim1", scenarioId: "s1",
        status: "running", currentRound: 3, currentPhaseIndex: 0,
        stateJSON: stateJSON, configJSON: nil,
        createdAt: Date(), updatedAt: Date()))

    // Fetch and decode
    let fetched = try repos.simulation.fetchById("sim1")!
    let decoded = try JSONDecoder().decode(
      SimulationState.self,
      from: Data(fetched.stateJSON.utf8))

    // Verify all fields survived the round-trip
    #expect(decoded.scores == state.scores)
    #expect(decoded.eliminated == state.eliminated)
    #expect(decoded.conversationLog.count == 1)
    #expect(decoded.conversationLog.first?.agentName == "Alice")
    #expect(decoded.lastOutputs["Alice"]?.statement == "Hello everyone")
    #expect(decoded.voteResults == state.voteResults)
    #expect(decoded.pairings.count == 1)
    #expect(decoded.pairings.first?.action1 == "cooperate")
    #expect(decoded.variables["topic"] == "weather")
    #expect(decoded.currentRound == 3)
  }

  @Test func multipleSimulationsPerScenario() throws {
    let repos = try makeRepos()

    try repos.scenario.save(
      ScenarioRecord(
        id: "s1", name: "Test", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    for i in 1...3 {
      try repos.simulation.save(
        SimulationRecord(
          id: "sim\(i)", scenarioId: "s1",
          status: i == 3 ? "running" : "completed",
          currentRound: 5, currentPhaseIndex: 0,
          stateJSON: "{}", configJSON: nil,
          createdAt: Date(), updatedAt: Date()))
    }

    let sims = try repos.simulation.fetchByScenarioId("s1")
    #expect(sims.count == 3)
  }
}
