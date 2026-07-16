import Testing

@testable import Pastura

/// Wiring-level gate for the #914 secrecy invariant: a persona's `secret`
/// reaches only the owning agent's **system** prompt, and never the user prompt
/// of any agent.
///
/// This drives the real assembly rather than mirroring it. The handlers build
/// the user prompt from `var variables = state.variables` plus the `inject*`
/// helpers (`SpeakEachHandler.swift`), so `state.variables` is the actual leak
/// surface: anything written there resolves into every agent's user prompt via
/// `expandTemplate`. These tests fail if a future change copies `secret` into a
/// state variable or grows a `{secret}`-style placeholder — the equivalent
/// `PromptBuilder`-level assertion could not, because `expandTemplate` is a pure
/// function over a dictionary the test itself would build.
///
/// Sibling of `AssignedPlaceholderInjectionTests` (#890), which guards the
/// mirror-image property for values that are *supposed* to be injected.
///
/// **Verified by mutation, not by assumption.** Two sabotage runs during review:
/// a `state.variables` write and a `conversationLog` append of the secret. Both
/// were caught (the shared-state write by `handlerNeverWritesSecretIntoStateVariables`,
/// the log append by that test *and* the user-prompt tests, since
/// `{conversation_log}` renders into every agent's prompt).
///
/// **Known blind spot — keep in mind when extending.** A write to the handler's
/// **local** `variables` copy is NOT caught unless some placeholder in the phase
/// template resolves it. That case is per-persona (the local dict is rebuilt per
/// agent), so it cannot leak *across* agents — which is why these tests target
/// the shared surfaces instead. If a `{secret}`-style engine-supplied
/// placeholder is ever added, extend `Self.template` to reference it so the
/// expansion assertions cover it.
@Suite(.timeLimit(.minutes(1)))
struct SecrecyInvariantTests {
  private static let aliceSecret = "ALICE_SECRET_SOLD_THE_HOUSE"
  private static let bobSecret = "BOB_SECRET_FORGED_THE_WILL"

  /// A template pulling every channel a handler injects, so a secret leaking
  /// through any of them surfaces in the expansion.
  private static let template =
    "LOG={conversation_log} SCORE={scoreboard} MINE={assigned} NOTES={my_notes} MOOD={my_mood}"

  private func secretScenario(phases: [Phase]) -> Scenario {
    let base = makeTestScenario(agentNames: ["Alice", "Bob"], phases: phases)
    return Scenario(
      id: base.id, name: base.name, description: base.description, language: base.language,
      agentCount: base.agentCount, rounds: base.rounds, context: base.context,
      personas: [
        Persona(name: "Alice", description: "A strategist", secret: Self.aliceSecret),
        Persona(name: "Bob", description: "An optimist", secret: Self.bobSecret)
      ],
      phases: base.phases)
  }

  @Test func speakAllKeepsSecretsOutOfEveryUserPrompt() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a", "inner_thought": "t"}"#, #"{"statement": "b", "inner_thought": "t"}"#
    ])
    try await mock.loadModel()
    let scenario = secretScenario(phases: [
      Phase(
        type: .speakAll, prompt: Self.template,
        outputSchema: ["statement": "string", "inner_thought": "string"])
    ])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await SpeakAllHandler().execute(context: context, state: &state)

    for captured in mock.capturedPrompts {
      #expect(!captured.user.contains(Self.aliceSecret))
      #expect(!captured.user.contains(Self.bobSecret))
    }
    // The system prompt is the sanctioned channel — and strictly per-owner.
    #expect(mock.capturedPrompts[0].system.contains(Self.aliceSecret))
    #expect(!mock.capturedPrompts[0].system.contains(Self.bobSecret))
    #expect(mock.capturedPrompts[1].system.contains(Self.bobSecret))
    #expect(!mock.capturedPrompts[1].system.contains(Self.aliceSecret))
  }

  /// The engine must not copy `secret` into `state.variables` — that dictionary
  /// is the base of every agent's user prompt, so a write there leaks to all.
  @Test func handlerNeverWritesSecretIntoStateVariables() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a", "inner_thought": "t"}"#, #"{"statement": "b", "inner_thought": "t"}"#
    ])
    try await mock.loadModel()
    let scenario = secretScenario(phases: [
      Phase(
        type: .speakAll, prompt: Self.template,
        outputSchema: ["statement": "string", "inner_thought": "string"])
    ])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await SpeakAllHandler().execute(context: context, state: &state)

    for (key, value) in state.variables {
      #expect(!value.contains(Self.aliceSecret), "secret leaked into state.variables['\(key)']")
      #expect(!value.contains(Self.bobSecret), "secret leaked into state.variables['\(key)']")
    }
    // Nor into the conversation log, which every agent's prompt renders.
    for entry in state.conversationLog {
      #expect(!entry.content.contains(Self.aliceSecret))
      #expect(!entry.content.contains(Self.bobSecret))
    }
  }

  /// speak_each accumulates the log across turns, so a leak into it would reach
  /// the *later* speakers' prompts specifically.
  @Test func speakEachKeepsSecretsOutOfLaterSpeakersPrompts() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "a", "inner_thought": "t"}"#, #"{"statement": "b", "inner_thought": "t"}"#
    ])
    try await mock.loadModel()
    let scenario = secretScenario(phases: [
      Phase(
        type: .speakEach, prompt: Self.template,
        outputSchema: ["statement": "string", "inner_thought": "string"], subRounds: 1)
    ])
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await SpeakEachHandler().execute(context: context, state: &state)

    let last = try #require(mock.capturedPrompts.last)
    #expect(!last.user.contains(Self.aliceSecret))
    #expect(!last.user.contains(Self.bobSecret))
  }
}
