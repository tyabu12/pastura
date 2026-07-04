import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ReflectHandlerTests {
  let handler = ReflectHandler()

  private func reflectPhase(prompt: String? = "Reflect!") -> Phase {
    Phase(type: .reflect, prompt: prompt, outputSchema: ["note": "string"])
  }

  @Test func storesNoteUnderNotesKeyForEachAgent() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": "Alice suspects Bob"}"#,
      #"{"note": "Bob trusts no one"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [reflectPhase()]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["notes_Alice"] == "Alice suspects Bob")
    #expect(state.variables["notes_Bob"] == "Bob trusts no one")
  }

  @Test func emitsAgentOutputWithReflectPhaseType() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": "a"}"#,
      #"{"note": "b"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [reflectPhase()]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let reflectAgents = collector.events.compactMap { event -> String? in
      if case .agentOutput(let agent, _, let phaseType) = event, phaseType == .reflect {
        return agent
      }
      return nil
    }
    #expect(reflectAgents == ["Alice", "Bob"])
  }

  @Test func doesNotAppendToConversationLog() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": "private memo"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [reflectPhase()]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.conversationLog.isEmpty)
  }

  @Test func doesNotUpdateLastOutputs() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": "private memo"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [reflectPhase()]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.lastOutputs["Alice"] == nil)
  }

  @Test func skipsEliminatedAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": "Alice note"}"#,
      #"{"note": "Charlie note"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      phases: [reflectPhase()]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
    #expect(state.variables["notes_Bob"] == nil)
    #expect(state.variables["notes_Alice"] == "Alice note")
    #expect(state.variables["notes_Charlie"] == "Charlie note")
  }

  // An empty note (LLM returned "" after exhausting the empty-field retry
  // budget) must NOT overwrite the previous round's memo. Three identical
  // empty responses cover maxRetries (2) + the initial attempt.
  @Test func emptyNoteDoesNotErasePreExistingNote() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": ""}"#,
      #"{"note": ""}"#,
      #"{"note": ""}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [reflectPhase()]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.variables["notes_Alice"] = "prior round memo"
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["notes_Alice"] == "prior round memo")
  }
}
