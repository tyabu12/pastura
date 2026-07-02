import Testing

@testable import Pastura

/// Wiring-level guard for #890: the `{assigned}` / `{assigned_word}`
/// placeholders must resolve to the *current speaker's* `assign`-phase
/// value at every per-persona LLM prompt-build site.
///
/// Unlike ``BundledPresetPlaceholderCoverageTests`` (which only proves a
/// token is *known* to `PromptPlaceholders.engineSupplied`), these tests
/// exercise the actual injection: they fail if `PromptBuilder.injectAssigned`
/// is ever removed from a handler, catching a #890 regression that the
/// static-set guard cannot see (critic Action 1).
@Suite(.timeLimit(.minutes(1)))
struct AssignedPlaceholderInjectionTests {
  private static let template = "MINE={assigned} ALIAS={assigned_word}"

  private func seedAssignments(_ state: inout SimulationState) {
    state.variables["assigned_Alice"] = "apple"
    state.variables["assigned_Bob"] = "orange"
  }

  @Test func speakAllInjectsAssignedPerPersona() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .speakAll, prompt: Self.template, outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedAssignments(&state)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await SpeakAllHandler().execute(context: context, state: &state)

    let alice = mock.capturedPrompts[0].user
    #expect(alice.contains("MINE=apple"))
    #expect(alice.contains("ALIAS=apple"))
    #expect(!alice.contains("{assigned}"))
    #expect(!alice.contains("{assigned_word}"))
    #expect(mock.capturedPrompts[1].user.contains("MINE=orange"))
  }

  @Test func speakEachInjectsAssignedPerPersona() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a"}"#, #"{"statement": "b"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(type: .speakEach, prompt: Self.template, outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedAssignments(&state)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await SpeakEachHandler().execute(context: context, state: &state)

    let alice = mock.capturedPrompts[0].user
    #expect(alice.contains("MINE=apple"))
    #expect(!alice.contains("{assigned_word}"))
    #expect(mock.capturedPrompts[1].user.contains("MINE=orange"))
  }

  @Test func voteInjectsAssignedPerPersona() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob"}"#, #"{"vote": "Alice"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .vote, prompt: Self.template, outputSchema: ["vote": "string"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedAssignments(&state)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await VoteHandler().execute(context: context, state: &state)

    let alice = mock.capturedPrompts[0].user
    #expect(alice.contains("MINE=apple"))
    #expect(!alice.contains("{assigned_word}"))
    #expect(mock.capturedPrompts[1].user.contains("MINE=orange"))
  }

  @Test func chooseRoundRobinInjectsSpeakerAssigned() async throws {
    // active.count == 2 → 2 pairs × 2 callAgent = 4 calls.
    // capturedPrompts[0] is Alice (speaker), [1] is Bob (speaker).
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#, #"{"action": "betray"}"#,
      #"{"action": "cooperate"}"#, #"{"action": "betray"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: Self.template,
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"], pairing: .roundRobin)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedAssignments(&state)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await ChooseHandler().execute(context: context, state: &state)

    let alice = mock.capturedPrompts[0].user
    #expect(alice.contains("MINE=apple"))
    #expect(!alice.contains("{assigned_word}"))
    #expect(mock.capturedPrompts[1].user.contains("MINE=orange"))
  }

  @Test func chooseIndividualInjectsAssignedPerPersona() async throws {
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate"}"#, #"{"action": "betray"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: Self.template,
          outputSchema: ["action": "string"],
          options: ["cooperate", "betray"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedAssignments(&state)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await ChooseHandler().execute(context: context, state: &state)

    let alice = mock.capturedPrompts[0].user
    #expect(alice.contains("MINE=apple"))
    #expect(!alice.contains("{assigned_word}"))
    #expect(mock.capturedPrompts[1].user.contains("MINE=orange"))
  }

  /// No assign phase ran → placeholder resolves to empty string, never a
  /// literal leak (matches EventInjectHandler's miss posture).
  @Test func missingAssignmentResolvesToEmptyNotLiteral() async throws {
    let mock = MockLLMService(responses: [#"{"statement": "a"}"#])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .speakAll, prompt: "[{assigned_word}]", outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await SpeakAllHandler().execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("[]"))
    #expect(!prompt.contains("{assigned_word}"))
  }
}
