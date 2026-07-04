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

  /// The user prompt's `{conversation_log}` expansion honors
  /// `scenario.logWindow` — only the last N prior entries reach the LLM (#907).
  @Test func userPromptRespectsLogWindow() async throws {
    let mock = MockLLMService(responses: [#"{"statement": "reply"}"#])
    try await mock.loadModel()

    let scenario = Scenario(
      id: "lw", name: "LW", description: "log window handler test",
      language: "en", agentCount: 1, rounds: 1, context: "Context",
      personas: [Persona(name: "Alice", description: "A")],
      phases: [
        Phase(
          type: .speakAll, prompt: "Log: {conversation_log}",
          outputSchema: ["statement": "string"])
      ],
      logWindow: 2)
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 2
    state.conversationLog = [
      ConversationEntry(agentName: "Alice", content: "oldest", phaseType: .speakAll, round: 1),
      ConversationEntry(agentName: "Bob", content: "middle", phaseType: .speakAll, round: 1),
      ConversationEntry(agentName: "Carol", content: "newest", phaseType: .speakAll, round: 1)
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let userPrompt = try #require(mock.capturedPrompts.first).user
    #expect(!userPrompt.contains("oldest"))
    #expect(userPrompt.contains("middle"))
    #expect(userPrompt.contains("newest"))
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

  // MARK: - simulationLanguage override (ADR-010 Step E)

  @Test func speakAllHonorsSimulationLanguageOverride_jaToEn() async throws {
    // Scenario: ja authoring, en simulation override. prompt:nil forces fallback.
    // The captured prompt must contain the English fallback, not the Japanese one.
    let mock = MockLLMService(responses: [
      #"{"statement": "hello"}"#,
      #"{"statement": "world"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "ja",
      simulationLanguage: "en",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [Phase(type: .speakAll, prompt: nil, outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("Share your opinion"))
    #expect(!prompt.contains("あなたの意見"))
  }

  @Test func speakAllHonorsSimulationLanguageOverride_enToJa() async throws {
    // Reverse: en authoring, ja simulation override. Captured prompt must contain Japanese.
    let mock = MockLLMService(responses: [
      #"{"statement": "hello"}"#,
      #"{"statement": "world"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "en",
      simulationLanguage: "ja",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [Phase(type: .speakAll, prompt: nil, outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("あなたの意見"))
    #expect(!prompt.contains("Share your opinion"))
  }
}
