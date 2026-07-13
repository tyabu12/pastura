import Testing

@testable import Pastura

/// Behavioral tests for `NarrateHandler` (#909): single-inference commentator,
/// non-participant semantics, and degrade-by-omission (empty-log / failure).
@Suite(.timeLimit(.minutes(1)))
struct NarrateHandlerTests {
  let handler = NarrateHandler()

  private func scenarioWithNarrate(narrator: String? = nil) -> Scenario {
    // Pin 3 agents explicitly: `singleInferenceRegardlessOfAgentCount` relies on
    // agentCount > 1 to prove per-round (not per-agent) inference, so it must not
    // silently weaken to 1 == 1 if `makeTestScenario`'s default ever changes.
    makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      phases: [Phase(type: .narrate, narrator: narrator)])
  }

  /// A state whose conversation log is non-empty (so narrate has facts to
  /// ground on and does not hit the empty-log skip).
  private func stateWithLog(for scenario: Scenario) -> SimulationState {
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.conversationLog = [
      ConversationEntry(
        agentName: "Alice", content: "I accuse Bob.", phaseType: .speakAll, round: 1),
      ConversationEntry(
        agentName: "Bob", content: "That is absurd.", phaseType: .speakAll, round: 1)
    ]
    return state
  }

  @Test func emitsNarrationOnSuccess() async throws {
    let mock = MockLLMService(responses: ["{\"commentary\": \"Alice went on the attack!\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = stateWithLog(for: scenario)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    let narrations = collector.events.compactMap { event -> String? in
      if case .narration(let text) = event { return text }
      return nil
    }
    #expect(narrations == ["Alice went on the attack!"])
  }

  @Test func singleInferenceRegardlessOfAgentCount() async throws {
    // 3 agents (Alice/Bob/Charlie) — narrate must still call the LLM exactly
    // ONCE (the narrator is not a participant; cost is agent-count-independent).
    let mock = MockLLMService(responses: ["{\"commentary\": \"A tense round.\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = stateWithLog(for: scenario)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    #expect(mock.capturedPrompts.count == 1)
  }

  @Test func narratorIsNotAParticipant() async throws {
    // The narrator must not pollute the conversation log / lastOutputs, and must
    // emit `.narration`, never `.agentOutput` — so it never enters votes,
    // scores, or the scoreboard.
    let mock = MockLLMService(responses: ["{\"commentary\": \"What a move.\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = stateWithLog(for: scenario)
    let logCountBefore = state.conversationLog.count
    let lastOutputsBefore = state.lastOutputs
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    // Conversation log + lastOutputs untouched (narrator is not a participant).
    #expect(state.conversationLog.count == logCountBefore)
    #expect(state.lastOutputs == lastOutputsBefore)
    // No agentOutput emitted for the narrator.
    let agentOutputs = collector.events.filter {
      if case .agentOutput = $0 { return true }
      return false
    }
    #expect(agentOutputs.isEmpty)
  }

  @Test func skipsEmissionOnEmptyLog() async throws {
    // Round 1 before any speak phase: nothing to narrate → no inference, no
    // event (the hallucination edge is answered by skipping, not inventing).
    let mock = MockLLMService(responses: ["{\"commentary\": \"should not fire\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = SimulationState.initial(for: scenario)  // empty conversation log
    state.currentRound = 1
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    #expect(mock.capturedPrompts.isEmpty)
    let narrations = collector.events.filter {
      if case .narration = $0 { return true }
      return false
    }
    #expect(narrations.isEmpty)
  }

  @Test func degradesByOmissionOnFailure() async throws {
    // LLM failure (exhausted responses → throws on every attempt) → no
    // `.narration`, no `.turnSkipped`, and execute does NOT throw: narrate
    // degrades by omission and bypasses the agent-attributed TurnFailureGate.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = stateWithLog(for: scenario)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)  // must NOT throw

    let narrations = collector.events.filter {
      if case .narration = $0 { return true }
      return false
    }
    #expect(narrations.isEmpty)
    let skipped = collector.events.filter {
      if case .turnSkipped = $0 { return true }
      return false
    }
    #expect(skipped.isEmpty)
  }

  @Test func skipsEmissionOnEmptyCommentary() async throws {
    // A parsed-but-empty commentary field must not emit a blank narration line.
    let mock = MockLLMService(responses: ["{\"commentary\": \"\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = stateWithLog(for: scenario)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    let narrations = collector.events.filter {
      if case .narration = $0 { return true }
      return false
    }
    #expect(narrations.isEmpty)
  }

  @Test func injectsNarratorDescriptorIntoSystemPrompt() async throws {
    // The optional `narrator:` descriptor shapes the commentator's voice — it
    // is injected into the Engine-owned system prompt.
    let mock = MockLLMService(responses: ["{\"commentary\": \"ok\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate(narrator: "熱血なスポーツ実況")
    var state = stateWithLog(for: scenario)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    #expect(mock.capturedPrompts.first?.system.contains("熱血なスポーツ実況") == true)
  }

  @Test func requestsCommentarySchema() async throws {
    // narrate uses an Engine-fixed single-field `{ commentary }` schema (not
    // author-declared), so the backend receives exactly that constraint.
    let mock = MockLLMService(responses: ["{\"commentary\": \"ok\"}"])
    try await mock.loadModel()
    let scenario = scenarioWithNarrate()
    var state = stateWithLog(for: scenario)
    let collector = EventCollector()
    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)

    try await handler.execute(context: context, state: &state)

    let schema = try #require(mock.capturedSchemas.first.flatMap { $0 })
    #expect(schema.fields.map(\.name) == ["commentary"])
  }
}
