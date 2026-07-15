import Testing

@testable import Pastura

/// Wiring-level guard for the mood output field (#913): every per-persona LLM
/// handler must (a) inject `{my_mood}` from the reserved `mood_<name>` key so a
/// carried-over mood reaches the prompt with no literal-brace leak, and (b)
/// capture a fresh non-empty `mood` output back into `mood_<name>`.
///
/// Unlike ``PromptBuilderTests`` (which exercises the helpers in isolation) and
/// the static `PlaceholderAvailability` map (which only proves the token is
/// *known*), these tests fail if `injectMood` / `captureMood` is ever dropped
/// from a handler — the map↔handler drift the critic flagged as untested,
/// including the easy-to-miss `choose` individual branch (mirrors
/// ``AssignedPlaceholderInjectionTests``).
@Suite(.timeLimit(.minutes(1)))
struct MoodPlaceholderInjectionTests {
  private static let template = "MOOD={my_mood}"

  private func seedMoods(_ state: inout SimulationState) {
    state.variables["mood_Alice"] = "calm"
    state.variables["mood_Bob"] = "tense"
  }

  @Test func speakAllInjectsAndCapturesMood() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a", "mood": "excited"}"#, #"{"statement": "b", "mood": "angry"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .speakAll, prompt: Self.template,
          outputSchema: ["statement": "string", "mood": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await SpeakAllHandler().execute(context: context, state: &state)

    let alice = mock.capturedPrompts[0].user
    #expect(alice.contains("MOOD=calm"))
    #expect(!alice.contains("{my_mood}"))
    #expect(mock.capturedPrompts[1].user.contains("MOOD=tense"))
    #expect(state.variables["mood_Alice"] == "excited")
    #expect(state.variables["mood_Bob"] == "angry")
  }

  @Test func speakEachInjectsAndCapturesMood() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a", "mood": "excited"}"#, #"{"statement": "b", "mood": "angry"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .speakEach, prompt: Self.template,
          outputSchema: ["statement": "string", "mood": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await SpeakEachHandler().execute(context: context, state: &state)

    #expect(mock.capturedPrompts[0].user.contains("MOOD=calm"))
    #expect(!mock.capturedPrompts[0].user.contains("{my_mood}"))
    #expect(state.variables["mood_Alice"] == "excited")
  }

  @Test func voteInjectsAndCapturesMood() async throws {
    let mock = MockLLMService(responses: [
      #"{"vote": "Bob", "mood": "excited"}"#, #"{"vote": "Alice", "mood": "angry"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .vote, prompt: Self.template, outputSchema: ["vote": "string", "mood": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await VoteHandler().execute(context: context, state: &state)

    #expect(mock.capturedPrompts[0].user.contains("MOOD=calm"))
    #expect(!mock.capturedPrompts[0].user.contains("{my_mood}"))
    #expect(state.variables["mood_Alice"] == "excited")
  }

  @Test func chooseRoundRobinInjectsAndCapturesMood() async throws {
    // round-robin runs 2 directed pairs (4 calls); Alice speaks in both, so her
    // last-write-wins capture depends on call order — keep every mood the same
    // value so the capture assertion is order-independent (the wiring, not the
    // ordering, is under test here).
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate", "mood": "excited"}"#, #"{"action": "betray", "mood": "excited"}"#,
      #"{"action": "cooperate", "mood": "excited"}"#, #"{"action": "betray", "mood": "excited"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: Self.template,
          outputSchema: ["action": "string", "mood": "string"],
          options: ["cooperate", "betray"], pairing: .roundRobin)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await ChooseHandler().execute(context: context, state: &state)

    #expect(mock.capturedPrompts[0].user.contains("MOOD=calm"))
    #expect(!mock.capturedPrompts[0].user.contains("{my_mood}"))
    #expect(state.variables["mood_Alice"] == "excited")
  }

  // The critic's flagged easy-miss branch: `choose` individual omits
  // injectWhispers but MUST still inject/capture mood (symmetric like notes).
  @Test func chooseIndividualInjectsAndCapturesMood() async throws {
    let mock = MockLLMService(responses: [
      #"{"action": "cooperate", "mood": "excited"}"#, #"{"action": "betray", "mood": "angry"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .choose, prompt: Self.template,
          outputSchema: ["action": "string", "mood": "string"],
          options: ["cooperate", "betray"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await ChooseHandler().execute(context: context, state: &state)

    #expect(mock.capturedPrompts[0].user.contains("MOOD=calm"))
    #expect(!mock.capturedPrompts[0].user.contains("{my_mood}"))
    #expect(state.variables["mood_Alice"] == "excited")
  }

  @Test func reflectInjectsAndCapturesMood() async throws {
    let mock = MockLLMService(responses: [
      #"{"note": "n1", "mood": "excited"}"#, #"{"note": "n2", "mood": "angry"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .reflect, prompt: Self.template,
          outputSchema: ["note": "string", "mood": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await ReflectHandler().execute(context: context, state: &state)

    #expect(mock.capturedPrompts[0].user.contains("MOOD=calm"))
    #expect(!mock.capturedPrompts[0].user.contains("{my_mood}"))
    #expect(state.variables["mood_Alice"] == "excited")
  }

  @Test func whisperInjectsAndCapturesMood() async throws {
    // 2 active agents, 1 sub_round → one pair × one exchange = 2 whisper turns
    // (Alice then Bob).
    let mock = MockLLMService(responses: [
      #"{"statement": "psst", "mood": "excited"}"#, #"{"statement": "back", "mood": "angry"}"#
    ])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [
        Phase(
          type: .whisper, prompt: Self.template,
          outputSchema: ["statement": "string", "mood": "string"], subRounds: 1)
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    seedMoods(&state)
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await WhisperHandler().execute(context: context, state: &state)

    #expect(mock.capturedPrompts[0].user.contains("MOOD=calm"))
    #expect(!mock.capturedPrompts[0].user.contains("{my_mood}"))
    #expect(state.variables["mood_Alice"] == "excited")
    #expect(state.variables["mood_Bob"] == "angry")
  }

  /// No prior mood → `{my_mood}` resolves to empty string, never a literal
  /// leak (matches the injectAssigned miss posture).
  @Test func missingMoodResolvesToEmptyNotLiteral() async throws {
    let mock = MockLLMService(responses: [#"{"statement": "a"}"#])
    try await mock.loadModel()
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .speakAll, prompt: "[{my_mood}]", outputSchema: ["statement": "string"])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: EventCollector())

    try await SpeakAllHandler().execute(context: context, state: &state)

    let prompt = mock.capturedPrompts[0].user
    #expect(prompt.contains("[]"))
    #expect(!prompt.contains("{my_mood}"))
  }
}
