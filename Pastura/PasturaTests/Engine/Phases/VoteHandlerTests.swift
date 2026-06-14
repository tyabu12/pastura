import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct VoteHandlerTests {
  let handler = VoteHandler()

  @Test func collectsVotesFromAllAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob", "reason": "suspicious"}"#,
      #"{"vote": "Alice", "reason": "quiet"}"#,
      #"{"vote": "Alice", "reason": "weird"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [
        Phase(
          type: .vote, prompt: "Vote!", outputSchema: ["vote": "string", "reason": "string"],
          excludeSelf: true)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.voteResults["Alice"] == 2)
    #expect(state.voteResults["Bob"] == 1)
    #expect(mock.generateCallCount == 3)
  }

  @Test func emitsVoteResultsEvent() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let voteEvents = collector.events.compactMap { event -> ([String: String], [String: Int])? in
      if case .voteResults(let votes, let tallies) = event { return (votes, tallies) }
      return nil
    }
    #expect(voteEvents.count == 1)
    #expect(voteEvents[0].0["Alice"] == "Bob")
    #expect(voteEvents[0].0["Bob"] == "Alice")
  }

  @Test func skipsEliminatedAgents() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Charlie"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.eliminated["Bob"] = true
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(mock.generateCallCount == 2)
  }

  @Test func populatesVoteResultsStateVariable() async throws {
    // Key must be "vote_results" (plural) to match the {vote_results} placeholder
    // documented in PhaseEditorSheet and used by the word_wolf preset.
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["vote_results"] == #"{"Alice": 2, "Bob": 1}"#)
    #expect(state.variables["vote_result"] == nil)
  }

  @Test func dropsInvalidVotesFromTally() async throws {
    // Regression for #524. Three voters (exclude_self default true):
    //   Alice → "Alice"   self-vote, invalid (Alice ∉ her candidates)
    //   Bob   → "Ghost"   hallucinated name, invalid
    //   Charlie → "Bob"   valid
    // Reverting the drop would put Alice (self) and Ghost back into the
    // tally — this test fails in that case.
    let mock = MockLLMService(responses: [
      #"{"vote": "Alice"}"#,
      #"{"vote": "Ghost"}"#,
      #"{"vote": "Bob"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Only Charlie's valid vote is tallied.
    #expect(state.voteResults == ["Bob": 1])
    #expect(state.voteResults["Alice"] == nil)  // self-vote dropped
    #expect(state.voteResults["Ghost"] == nil)  // hallucinated dropped

    // Divergence is intentional: the raw votes stay visible in the
    // voteResults event even though they are absent from the tally.
    let voteEvent = collector.events.compactMap { event -> [String: String]? in
      if case .voteResults(let votes, _) = event { return votes }
      return nil
    }.first
    let votes = try #require(voteEvent)
    #expect(votes["Alice"] == "Alice")  // self-vote preserved in votes map
    #expect(votes["Bob"] == "Ghost")  // hallucinated preserved in votes map
    #expect(votes["Charlie"] == "Bob")
  }

  // MARK: - Per-voter enumeration schema (#524)

  /// Extract the `vote` field's kind from the schema captured on the Nth
  /// `generate` call (one per voter, in persona order).
  private func voteKind(
    _ mock: MockLLMService, call index: Int
  ) throws -> OutputSchema.Kind {
    let schema = try #require(mock.capturedSchemas[index])
    let voteField = try #require(schema.fields.first { $0.name == "vote" })
    return voteField.kind
  }

  @Test func voteSchemaConstrainsVoteToCandidates() async throws {
    // exclude_self (default true) → each voter's candidate list omits self.
    // The schema passed for voter Alice must enumerate [Bob, Charlie].
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Charlie"}"#,
      #"{"vote": "Bob"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Alice (call 0) cannot vote herself; Charlie (call 2) cannot vote himself.
    #expect(try voteKind(mock, call: 0) == .enumeration(["Bob", "Charlie"]))
    #expect(try voteKind(mock, call: 2) == .enumeration(["Alice", "Bob"]))
  }

  @Test func voteSchemaConstrainsCJKCandidates() async throws {
    // The grammar enumeration must carry CJK persona names verbatim — this
    // is the scenario-factory's primary workload (#524 was observed on
    // Japanese-named personas).
    let mock = MockLLMService(responses: [
      #"{"vote": "博士マッド野"}"#,
      #"{"vote": "体験者ミラクル子"}"#,
      #"{"vote": "開き直りマコ"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["開き直りマコ", "博士マッド野", "体験者ミラクル子"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(
      try voteKind(mock, call: 0) == .enumeration(["博士マッド野", "体験者ミラクル子"]))
    // Assert a second voter too, so an ordering / filter regression on
    // multi-byte names can't slip through on a single-call lock.
    #expect(
      try voteKind(mock, call: 2) == .enumeration(["開き直りマコ", "博士マッド野"]))
  }

  @Test func voteSchemaFallsBackToStringForUnsafeCandidate() async throws {
    // A persona name containing a GBNF-hostile char (`"`) would make the
    // enumeration grammar throw and abort the run. The voter whose
    // candidate list includes that name must degrade to `.string`.
    let unsafeName = #"Ali"ce"#
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Charlie"}"#,
      #"{"vote": "Bob"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: [unsafeName, "Bob", "Charlie"],
      phases: [Phase(type: .vote, prompt: "Vote!", outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Voter 0 (unsafe name) excludes self → candidates [Bob, Charlie], all
    // safe → still enumerated.
    #expect(try voteKind(mock, call: 0) == .enumeration(["Bob", "Charlie"]))
    // Voter 1 (Bob) → candidates [Ali"ce, Charlie] include the unsafe name
    // → fall back to `.string` rather than abort.
    #expect(try voteKind(mock, call: 1) == .string)
  }

  // MARK: - simulationLanguage override (ADR-010 Step E)

  @Test func voteHonorsSimulationLanguageOverride_jaToEn() async throws {
    // Scenario: ja authoring, en simulation override. prompt:nil forces fallback.
    // The captured prompt must contain the English fallback, not the Japanese one.
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "ja",
      simulationLanguage: "en",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [Phase(type: .vote, prompt: nil, outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("Vote for the person"))
    #expect(!prompt.contains("最も怪しい"))
  }

  @Test func voteHonorsSimulationLanguageOverride_enToJa() async throws {
    // Reverse: en authoring, ja simulation override. Captured prompt must contain Japanese.
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#,
      #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()

    let scenario = ScenarioFixture.make(
      language: "en",
      simulationLanguage: "ja",
      personas: [
        Persona(name: "Alice", description: "A test persona"),
        Persona(name: "Bob", description: "A test persona")
      ],
      phases: [Phase(type: .vote, prompt: nil, outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("最も怪しい"))
    #expect(!prompt.contains("Vote for the person"))
  }
}
