import Testing

@testable import Pastura

struct SpeakEachHandlerTests {
  let handler = SpeakEachHandler()

  @Test func executesSubRoundsInOrder() async throws {
    // 2 agents × 2 subRounds = 4 LLM calls
    let mock = MockLLMService(responses: [
      #"{"statement": "A1"}"#,
      #"{"statement": "B1"}"#,
      #"{"statement": "A2"}"#,
      #"{"statement": "B2"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"], subRounds: 2)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 4)
  }

  @Test func accumulatesConversationWithinSubRounds() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#,
      #"{"statement": "third"}"#,
      #"{"statement": "fourth"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .speakEach, prompt: "{conversation_log}", outputSchema: ["statement": "string"],
          subRounds: 2)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // All 4 entries should be in the conversation log
    #expect(state.conversationLog.count == 4)
    #expect(state.conversationLog[0].content == "first")
    #expect(state.conversationLog[3].content == "fourth")
  }

  @Test func defaultsToOneSubRound() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
  }

  @Test func skipsEliminatedAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "only Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 1)
  }
}
