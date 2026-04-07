import Testing

@testable import Pastura

struct SummarizeHandlerTests {
  let handler = SummarizeHandler()

  @Test func expandsTemplateWithVariables() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize, template: "Round {current_round} done")]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 3
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0] == "Round 3 done")
  }

  @Test func expandsPairingTemplate() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [
        Phase(type: .summarize, template: "{agent1}({action1}) vs {agent2}({action2})")
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    state.pairings = [
      Pairing(agent1: "Alice", agent2: "Bob", action1: "cooperate", action2: "betray")
    ]
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries[0] == "Alice(cooperate) vs Bob(betray)")
  }

  @Test func emitsSummaryEvent() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      phases: [Phase(type: .summarize)]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
  }
}
