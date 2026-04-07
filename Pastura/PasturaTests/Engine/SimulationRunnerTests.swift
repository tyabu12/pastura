import Foundation
import Testing

@testable import Pastura

// Serialized: SimulationRunner tests create Tasks and AsyncStreams that can
// interfere with each other when run in parallel on the simulator.
@Suite(.serialized)
struct SimulationRunnerTests {

  @Test func emitsFullLifecycleEvents() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(runner.run(scenario: scenario, llm: mock))

    // Round lifecycle
    #expect(
      events.contains {
        if case .roundStarted(let r, let t) = $0 { return r == 1 && t == 1 }
        return false
      })
    #expect(
      events.contains {
        if case .roundCompleted(let r, _) = $0 { return r == 1 }
        return false
      })

    // Phase lifecycle
    #expect(
      events.contains {
        if case .phaseStarted(let t, _) = $0 { return t == .speakAll }
        return false
      })
    #expect(
      events.contains {
        if case .phaseCompleted(let t, _) = $0 { return t == .speakAll }
        return false
      })

    // Simulation completed
    #expect(
      events.contains {
        if case .simulationCompleted = $0 { return true }
        return false
      })
  }

  @Test func executesMultipleRoundsAndResetsLog() async throws {
    // Need ≥2 agents (runner skips rounds when activeCount < 2)
    let mock = MockLLMService(responses: [
      // Round 1: Alice and Bob
      #"{"statement": "round1-alice"}"#,
      #"{"statement": "round1-bob"}"#,
      // Round 2: Alice and Bob
      #"{"statement": "round2-alice"}"#,
      #"{"statement": "round2-bob"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 2,
      phases: [
        Phase(
          type: .speakAll, prompt: "Log: {conversation_log}",
          outputSchema: ["statement": "string"])
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(runner.run(scenario: scenario, llm: mock))

    // Verify 2 rounds executed
    let roundStarts = events.filter {
      if case .roundStarted = $0 { return true }
      return false
    }
    #expect(roundStarts.count == 2)

    // Verify conversation log resets each round:
    // Round 2's first prompt (3rd call, index 2) should have empty log
    let prompts = mock.capturedPrompts
    #expect(prompts.count == 4)
    #expect(prompts[2].user.contains("（まだなし）"))
  }

  @Test func stopsWhenFewerThan2ActiveAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Bob"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 3,
      phases: [
        Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"]),
        Phase(type: .eliminate)
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(runner.run(scenario: scenario, llm: mock))

    let roundStarts = events.filter {
      if case .roundStarted = $0 { return true }
      return false
    }
    #expect(roundStarts.count == 1)

    #expect(
      events.contains {
        if case .simulationCompleted = $0 { return true }
        return false
      })
  }

  @Test func emitsValidationError() async throws {
    let mock = MockLLMService(responses: [])

    let scenario = makeTestScenario(
      agentNames: (0..<11).map { "Agent\($0)" },
      rounds: 1,
      phases: [Phase(type: .speakAll)]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(runner.run(scenario: scenario, llm: mock))

    #expect(
      events.contains {
        if case .error(.scenarioValidationFailed) = $0 { return true }
        return false
      })
  }

  @Test func fullPrisonersDilemmaIntegration() async throws {
    let mock = MockLLMService(responses: [
      #"{"declaration": "I'll cooperate!", "inner_thought": "lying"}"#,
      #"{"declaration": "Let's work together", "inner_thought": "maybe"}"#,
      #"{"action": "betray"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "cooperate"}"#,
      #"{"action": "betray"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .speakAll, prompt: "Declare!",
          outputSchema: ["declaration": "string", "inner_thought": "string"]
        ),
        Phase(
          type: .choose, prompt: "Opponent: {opponent_name}",
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        ),
        Phase(type: .scoreCalc, logic: .prisonersDilemma),
        Phase(type: .summarize, template: "Round {current_round} complete")
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(runner.run(scenario: scenario, llm: mock))

    #expect(
      events.contains {
        if case .simulationCompleted = $0 { return true }
        return false
      })

    let scoreUpdates = events.compactMap { event -> [String: Int]? in
      if case .scoreUpdate(let scores) = event { return scores }
      return nil
    }
    #expect(!scoreUpdates.isEmpty)

    let summaries = events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("Round 1 complete"))
  }

  // MARK: - Helpers

  private func collectAllEvents(_ stream: AsyncStream<SimulationEvent>) async -> [SimulationEvent] {
    var events: [SimulationEvent] = []
    for await event in stream {
      events.append(event)
    }
    return events
  }
}
