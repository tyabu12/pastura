import Foundation
import Testing

@testable import Pastura

// Serialized: SimulationRunner tests create Tasks and AsyncStreams that can
// interfere with each other when run in parallel on the simulator.
@Suite(.serialized)
// swiftlint:disable:next type_body_length
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
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    // Round lifecycle
    #expect(events.contains { if case .roundStarted(1, 1) = $0 { true } else { false } })
    #expect(events.contains { if case .roundCompleted(1, _) = $0 { true } else { false } })

    // Phase lifecycle
    #expect(events.contains { if case .phaseStarted(.speakAll, _) = $0 { true } else { false } })
    #expect(events.contains { if case .phaseCompleted(.speakAll, _) = $0 { true } else { false } })

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
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

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
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

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

    // Should emit a summary explaining why the simulation ended early
    let summaries = events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains { $0.contains("fewer than 2") })
  }

  @Test func emitsValidationError() async throws {
    let mock = MockLLMService(responses: [])

    let scenario = makeTestScenario(
      agentNames: (0..<11).map { "Agent\($0)" },
      rounds: 1,
      phases: [Phase(type: .speakAll)]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    #expect(
      events.contains {
        if case .error(.scenarioValidationFailed) = $0 { return true }
        return false
      })
  }

  // MARK: - Pause behavior

  @Test func emitsPausedEventOnlyOnce() async throws {
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
    runner.isPaused = true

    let stream = runner.run(scenario: scenario, llm: mock, suspendController: SuspendController())

    // Collect events concurrently while we control the pause state.
    // The sleep verifies that only one event is emitted regardless of
    // how long the pause lasts (signal-based, no polling).
    async let allEvents = collectAllEvents(stream)
    try await Task.sleep(for: .milliseconds(350))
    runner.isPaused = false
    let events = await allEvents

    let pausedEvents = events.filter {
      if case .simulationPaused = $0 { return true }
      return false
    }
    #expect(pausedEvents.count == 1)
    #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })
  }

  @Test func cancellationDuringPauseDoesNotHang() async throws {
    let mock = MockLLMService(responses: [])

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let runner = SimulationRunner()
    runner.isPaused = true

    let stream = runner.run(scenario: scenario, llm: mock, suspendController: SuspendController())

    // Collect events inside the task to avoid cross-task mutable capture.
    let consumer = Task<[SimulationEvent], Never> {
      await collectAllEvents(stream)
    }

    // Wait for the paused event to be emitted, then cancel.
    // When the consumer task is cancelled, the stream terminates and
    // triggers onTermination which cancels the runner's inner task.
    // The runner's .error(.cancelled) is emitted after the consumer stops
    // listening, so we only verify that:
    // 1) exactly one simulationPaused event was received, and
    // 2) cancellation during pause does not hang (test completes).
    try await Task.sleep(for: .milliseconds(50))
    consumer.cancel()
    let events = await consumer.value

    let pausedEvents = events.filter {
      if case .simulationPaused = $0 { return true }
      return false
    }
    #expect(pausedEvents.count == 1)
  }

  @Test func pausesBetweenPhasesNotOnlyBetweenRounds() async throws {
    // 2 agents, 1 round, 2 speak_all phases → 4 mock responses total
    let mock = MockLLMService(responses: [
      #"{"statement": "p0-alice"}"#,
      #"{"statement": "p0-bob"}"#,
      #"{"statement": "p1-alice"}"#,
      #"{"statement": "p1-bob"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .speakAll, prompt: "Phase 0", outputSchema: ["statement": "string"]),
        Phase(type: .speakAll, prompt: "Phase 1", outputSchema: ["statement": "string"])
      ]
    )

    let runner = SimulationRunner()
    runner.isPaused = true

    let stream = runner.run(scenario: scenario, llm: mock, suspendController: SuspendController())
    async let allEvents = collectAllEvents(stream)

    // Pause 1: round boundary — wait for runner to reach it
    try await Task.sleep(for: .milliseconds(50))

    // Resume + immediately re-pause: cooperative concurrency means the
    // runner task is enqueued but hasn't executed yet, so it will see
    // isPaused=true at the next checkpoint (executePhases phaseIndex 0).
    runner.isPaused = false
    runner.isPaused = true
    try await Task.sleep(for: .milliseconds(50))

    // Resume + immediately re-pause: runner executes phase 0 (fast mock),
    // then hits checkPaused at phaseIndex 1.
    runner.isPaused = false
    runner.isPaused = true
    try await Task.sleep(for: .milliseconds(100))

    // Final resume — let simulation complete
    runner.isPaused = false

    let events = await allEvents

    let pausedEvents = events.compactMap { event -> (Int, Int)? in
      if case .simulationPaused(let round, let phaseIndex) = event {
        return (round, phaseIndex)
      }
      return nil
    }

    // 3 pause events:
    // 1. Round boundary (round: 1, phaseIndex: 0)
    // 2. Before phase 0 in executePhases (round: 1, phaseIndex: 0)
    // 3. Before phase 1 in executePhases (round: 1, phaseIndex: 1)
    #expect(pausedEvents.count == 3, "Expected 3 pause events, got \(pausedEvents)")
    #expect(
      pausedEvents.contains { $0 == (1, 1) },
      "Should pause before phase 1 with phaseIndex=1, got \(pausedEvents)"
    )
    #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })
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
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

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

  // MARK: - Suspend controller propagation

  @Test func runnerPropagatesSuspendControllerToHandlers() async throws {
    // The controller passed to runner.run must reach LLMCaller via PhaseContext —
    // an external resume() on the same instance must unstick the parked call.
    // If propagation broke (e.g. each phase received a fresh controller),
    // resume on the test-owned instance would have no effect and the simulation
    // would never complete.
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let controller = SuspendController()
    await mock.attachSuspendController(controller)
    // Pre-suspend so the very first generate throws .suspended.
    controller.requestSuspend()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    // Resume after the first generate has parked on awaitResume.
    Task {
      try await Task.sleep(for: .milliseconds(50))
      controller.resume()
    }

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: controller)
    )

    #expect(
      events.contains {
        if case .simulationCompleted = $0 { return true }
        return false
      })
  }
}
