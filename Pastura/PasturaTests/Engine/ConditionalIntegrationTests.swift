import Foundation
import Testing

@testable import Pastura

/// End-to-end integration for the `conditional` phase type via
/// `SimulationRunner`. Exercises both branches, nested `phasePath`
/// emission, and pause semantics across sub-phases.
///
/// `@Suite(.serialized)` is required per `.claude/rules/testing.md`:
/// the runner spawns Tasks and AsyncStreams whose cleanup races under
/// parallel test execution.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ConditionalIntegrationTests {

  // MARK: - True branch end-to-end

  @Test func trueBranchExecutesThenSubPhases() async throws {
    // 2 agents × 1 round × (speak_all then conditional). Mock produces 2
    // responses for the top-level speak_all phase; the conditional's
    // then-branch is a code phase (summarize), no more inferences needed.
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"]),
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [Phase(type: .summarize, template: "then ran")],
          elsePhases: [Phase(type: .summarize, template: "else ran")]
        )
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    let summaries = events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("then ran"))
    #expect(!summaries.contains("else ran"))

    // conditionalEvaluated event fired with result=true.
    let evalEvents = events.compactMap { event -> (String, Bool)? in
      if case .conditionalEvaluated(let cond, let result) = event { return (cond, result) }
      return nil
    }
    #expect(evalEvents.count == 1)
    #expect(evalEvents[0].0 == "current_round == 1")
    #expect(evalEvents[0].1 == true)
  }

  // MARK: - False branch end-to-end

  @Test func falseBranchExecutesElseSubPhases() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"]),
        Phase(
          type: .conditional,
          condition: "current_round == 99",  // never true in a 1-round scenario
          thenPhases: [Phase(type: .summarize, template: "then ran")],
          elsePhases: [Phase(type: .summarize, template: "else ran")]
        )
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    let summaries = events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("else ran"))
    #expect(!summaries.contains("then ran"))
  }

  // MARK: - Nested phasePath is emitted

  @Test func innerLifecycleEventsCarryNestedPath() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            Phase(type: .summarize, template: "s0"),
            Phase(type: .summarize, template: "s1")
          ]
        )
      ]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    // Top-level `.phaseStarted(.conditional, [0])` + two nested
    // `.phaseStarted(.summarize, [0, 0])` / `([0, 1])`.
    let startedPaths = events.compactMap { event -> (PhaseType, [Int])? in
      if case .phaseStarted(let type, let path) = event { return (type, path) }
      return nil
    }
    #expect(startedPaths.contains { $0.0 == .conditional && $0.1 == [0] })
    #expect(startedPaths.contains { $0.0 == .summarize && $0.1 == [0, 0] })
    #expect(startedPaths.contains { $0.0 == .summarize && $0.1 == [0, 1] })
  }

  // MARK: - Pause between sub-phases

  #if DEBUG
    @Test func pauseBetweenSubPhasesEmitsSimulationPausedOncePerCycle() async throws {
      // Conditional with two sub-phases. With isPaused=true from the start,
      // the runner pauses before each of: round boundary, the outer
      // conditional phase, the first nested sub-phase, and the second.
      // Each pause must emit exactly one `.simulationPaused` event.
      let mock = MockLLMService(responses: [])
      let scenario = makeTestScenario(
        agentNames: ["Alice", "Bob"],
        rounds: 1,
        phases: [
          Phase(
            type: .conditional,
            condition: "current_round == 1",
            thenPhases: [
              Phase(type: .summarize, template: "s0"),
              Phase(type: .summarize, template: "s1")
            ]
          )
        ]
      )

      let runner = SimulationRunner()
      runner.isPaused = true

      let stream = runner.run(scenario: scenario, llm: mock, suspendController: SuspendController())

      // Single-consumer drain: mirror the pattern in
      // `SimulationRunnerTests.pausesBetweenPhasesNotOnlyBetweenRounds`.
      var events: [SimulationEvent] = []
      var pauseCount = 0
      for await event in stream {
        events.append(event)
        if case .simulationPaused = event {
          pauseCount += 1
          // Drive forward until the last expected pause, then release.
          if pauseCount < 4 {
            runner.resumeOnce()
          } else {
            runner.isPaused = false
          }
        }
      }

      // 4 paths observed: [] (round boundary), [0] (outer conditional),
      // [0, 0] (first sub-phase), [0, 1] (second sub-phase). Each path
      // fires exactly one `.simulationPaused`.
      let pausePaths = events.compactMap { event -> [Int]? in
        if case .simulationPaused(_, let path) = event { return path }
        return nil
      }
      #expect(pausePaths == [[], [0], [0, 0], [0, 1]])
      #expect(events.contains { if case .simulationCompleted = $0 { true } else { false } })
    }
  #endif
}
