import Foundation
import Testing

@testable import Pastura

/// End-to-end integration for the `event_inject` phase type via
/// `SimulationRunner`. Verifies the lifecycle pairing
/// `[.phaseStarted(.eventInject), .eventInjected(_), .phaseCompleted(.eventInject)]`
/// holds even on a probability "miss" — the runner emits the bracketing
/// pair regardless of inner outcome, so consumers can rely on every
/// phaseStarted having a matching phaseCompleted.
///
/// `@Suite(.serialized)` is required per `.claude/rules/testing.md`:
/// the runner spawns Tasks and AsyncStreams whose cleanup races under
/// parallel test execution.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct EventInjectIntegrationTests {

  // MARK: - Lifecycle pairing on miss

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  @Test func lifecyclePairingHoldsOnProbabilityMiss() async throws {
    // probability = 0 → roll always loses → `.eventInjected(nil)`.
    // Critic v3 requirement: verify the runner's
    // `.phaseStarted` / `.phaseCompleted` still bracket the inner
    // miss event so downstream consumers stay synced.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .eventInject, source: "events", probability: 0.0)
      ],
      extraData: ["events": .array(["x"])]
    )

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    // Slice down to the run of events around the event_inject phase.
    // The runner brackets every phase with phaseStarted / phaseCompleted
    // (path = [0] for the only top-level phase).
    let phaseSlice = events.compactMap { event -> (PhaseType, [Int])? in
      switch event {
      case .phaseStarted(let type, let path):
        return (type, path)
      case .phaseCompleted(let type, let path):
        return (type, path)
      default:
        return nil
      }
    }
    let injectEvents = events.filter { event in
      if case .eventInjected = event { return true }
      return false
    }

    // Exactly one phaseStarted/Completed pair for the eventInject phase.
    let started = phaseSlice.filter { type, _ in type == .eventInject }
    #expect(started.count == 2, "Expected one .phaseStarted + .phaseCompleted pair, got \(started)")
    #expect(injectEvents.count == 1)

    // Order: phaseStarted comes before .eventInjected, which comes
    // before phaseCompleted.
    let firstStartedIndex = events.firstIndex { event in
      if case .phaseStarted(.eventInject, _) = event { return true }
      return false
    }
    let injectIndex = events.firstIndex { event in
      if case .eventInjected = event { return true }
      return false
    }
    let completedIndex = events.firstIndex { event in
      if case .phaseCompleted(.eventInject, _) = event { return true }
      return false
    }
    #expect(firstStartedIndex != nil)
    #expect(injectIndex != nil)
    #expect(completedIndex != nil)
    if let started = firstStartedIndex, let inject = injectIndex, let completed = completedIndex {
      #expect(started < inject)
      #expect(inject < completed)
    }

    // Miss payload: the inner event is `nil`.
    let payloads: [String?] = events.compactMap { event in
      if case .eventInjected(let value) = event { return value }
      return nil
    }
    // compactMap collapses nil — manually count to preserve the miss.
    var missCount = 0
    for event in events {
      if case .eventInjected(.none) = event { missCount += 1 }
    }
    #expect(missCount == 1, "Expected one miss event; got payloads=\(payloads)")
  }

  // MARK: - Variable surfacing in subsequent prompt

  @Test func injectedValueExpandsInDownstreamPrompt() async throws {
    // event_inject sets {current_event}; speak_all references it in its
    // prompt. The first thing we verify is that the prompt the LLM saw
    // contained the injected text — that's the contract that lets
    // curators rely on event_inject for narrative side-effects.
    let mock = MockLLMService(responses: [
      #"{"statement": "ack"}"#,
      #"{"statement": "ack"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .eventInject,
          source: "events", probability: 1.0
        ),
        Phase(
          type: .speakAll,
          prompt: "Event: {current_event}",
          outputSchema: ["statement": "string"]
        )
      ],
      extraData: ["events": .array(["停電"])]
    )

    let runner = SimulationRunner()
    _ = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    // Both agents should have seen "Event: 停電" in their user prompts.
    let promptsWithEvent = mock.capturedPrompts.filter { $0.user.contains("停電") }
    #expect(promptsWithEvent.count == 2)
  }
}
