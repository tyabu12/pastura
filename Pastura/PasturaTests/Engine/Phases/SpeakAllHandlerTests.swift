import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct SpeakAllHandlerTests {
  let handler = SpeakAllHandler()

  @Test func callsLLMForEachActiveAgent() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hello from Alice"}"#,
      #"{"statement": "hello from Bob"}"#,
      #"{"statement": "hello from Charlie"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 3)
  }

  @Test func skipsEliminatedAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hello from Alice"}"#,
      #"{"statement": "hello from Charlie"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
  }

  @Test func emitsAgentOutputForEachAgent() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .speakAll, prompt: "Go", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let agentOutputs = collector.events.compactMap { event -> String? in
      if case .agentOutput(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(agentOutputs == ["Alice", "Bob"])
  }

  @Test func updatesConversationLog() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "Alice says hi"}"#,
      #"{"statement": "Bob says hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .speakAll, prompt: "Go", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.conversationLog.count == 2)
    #expect(state.conversationLog[0].agentName == "Alice")
    #expect(state.conversationLog[0].content == "Alice says hi")
    #expect(state.conversationLog[1].agentName == "Bob")
  }

  @Test func updatesLastOutputs() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "test output"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .speakAll, prompt: "Go", outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.lastOutputs["Alice"]?.statement == "test output")
  }
}
