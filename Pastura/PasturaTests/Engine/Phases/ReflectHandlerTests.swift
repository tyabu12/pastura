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
  //
  // The MECHANISM changed under ADR-021 § Amendment 2026-08-06 while the
  // outcome did not: `note` is the canonical primary for `.reflect` and the
  // phase declares it, so exhaustion now throws and `TurnFailureGate` skips
  // the turn — the handler never reaches its non-empty save guard. The
  // `.turnSkipped` assertion below is what pins that; without it this test
  // would keep passing off the old guard and could not tell the two apart.
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

    let skipped = collector.events.compactMap { event -> String? in
      if case .turnSkipped(let agent, _, _) = event { return agent }
      return nil
    }
    #expect(skipped == ["Alice"], "exhausted empty primary skips the turn")
    #expect(
      !collector.events.contains { if case .agentOutput = $0 { return true } else { return false } }
    )
  }
}
