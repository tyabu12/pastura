import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
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

  // MARK: - subRounds clamp (untrusted YAML guard, #1064)

  // `subRounds: 0` would form the invalid ClosedRange `1...0` and trap the
  // app pre-fix. The clamp (`max(1, …)`) makes it behave as one sub-round —
  // exactly one pass over the personas. Reverting the clamp line must crash
  // this test, not merely change its pass mode.
  @Test func zeroSubRoundsRunsOncePerPersona() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "A1"}"#,
      #"{"statement": "B1"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"], subRounds: 0)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // 2 agents × 1 clamped sub-round = 2 calls (no trap).
    #expect(mock.generateCallCount == 2)
  }

  @Test func negativeSubRoundsRunsOncePerPersona() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "A1"}"#,
      #"{"statement": "B1"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"], subRounds: -1)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
  }

  // MARK: - simulationLanguage override (ADR-010 Step E)

  @Test func speakEachHonorsSimulationLanguageOverride_jaToEn() async throws {
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
      phases: [Phase(type: .speakEach, prompt: nil, outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("Conversation so far"))
    #expect(!prompt.contains("これまでの会話"))
  }

  @Test func speakEachHonorsSimulationLanguageOverride_enToJa() async throws {
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
      phases: [Phase(type: .speakEach, prompt: nil, outputSchema: ["statement": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("これまでの会話"))
    #expect(!prompt.contains("Conversation so far"))
  }

  // MARK: - Anti-repetition seed plumbing (#1105)

  // The DRY seam: each agent's turn seeds the sampler with its OWN most-recent
  // statement — still in `lastOutputs` because that's overwritten only after
  // the turn succeeds. First sub-round has no prior → empty seed; the second
  // sub-round seeds each agent with its first-sub-round statement (per agent,
  // not the globally-last one). The DRY sampler body itself is llama.cpp-only
  // and unrunnable in the simulator (PR #463); this pins the Engine-side
  // plumbing that decides WHAT gets seeded, which is where the #912 prompt-side
  // No-Go is actually addressed.
  @Test func seedsOwnPriorStatementPerAgentAcrossSubRounds() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "alice-r1"}"#,
      #"{"statement": "bob-r1"}"#,
      #"{"statement": "alice-r2"}"#,
      #"{"statement": "bob-r2"}"#
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

    // Call order: Alice-r1, Bob-r1, Alice-r2, Bob-r2.
    #expect(mock.capturedAntiRepetitionSeeds.count == 4)
    #expect(mock.capturedAntiRepetitionSeeds[0].isEmpty)  // Alice — no prior yet
    #expect(mock.capturedAntiRepetitionSeeds[1].isEmpty)  // Bob — no prior yet
    #expect(mock.capturedAntiRepetitionSeeds[2] == ["alice-r1"])  // Alice's own
    #expect(mock.capturedAntiRepetitionSeeds[3] == ["bob-r1"])  // Bob's own
  }

  // A whitespace-only prior statement must NOT seed — the handler's
  // `.filter { !trimmingCharacters(...).isEmpty }` drops it (an empty/"..."
  // statement is already caught upstream by the empty-field retry, but a
  // blank-but-nonempty one like "   " slips through to `lastOutputs`).
  // Reverting the filter makes this seed `["   "]` and fails the test.
  @Test func whitespaceOnlyPriorDoesNotSeed() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "   "}"#,
      #"{"statement": "alice-r2"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .speakEach, prompt: "Talk", outputSchema: ["statement": "string"], subRounds: 2)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.capturedAntiRepetitionSeeds.count == 2)
    #expect(mock.capturedAntiRepetitionSeeds[0].isEmpty)  // no prior
    #expect(mock.capturedAntiRepetitionSeeds[1].isEmpty)  // blank prior filtered out
  }
}
