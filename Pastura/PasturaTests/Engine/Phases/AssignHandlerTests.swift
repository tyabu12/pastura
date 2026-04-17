import Testing

@testable import Pastura

struct AssignHandlerTests {
  let handler = AssignHandler()

  @Test func assignsToAllAgents() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .assign, source: "topics", target: .all)],
      extraData: ["topics": .array(["Topic A", "Topic B"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["assigned_topic"] == "Topic A")
    #expect(state.variables["assigned_Alice"] == "Topic A")
    #expect(state.variables["assigned_Bob"] == "Topic A")
  }

  @Test func assignsRoundIndexedItem() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .assign, source: "topics", target: .all)],
      extraData: ["topics": .array(["First", "Second", "Third"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 2  // Should get "Second" (index 1)
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["assigned_topic"] == "Second")
  }

  @Test func assignsRandomOneForWordwolf() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      phases: [Phase(type: .assign, source: "words", target: .randomOne)],
      extraData: [
        "words": .arrayOfDictionaries([
          ["majority": "りんご", "minority": "みかん"]
        ])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // One agent should be the wolf
    let wolfName = state.variables["wolf_name"]
    #expect(wolfName != nil)
    #expect(["Alice", "Bob", "Charlie"].contains(wolfName!))

    // Wolf gets minority, others get majority
    #expect(state.variables["assigned_\(wolfName!)"] == "みかん")
    let nonWolves = ["Alice", "Bob", "Charlie"].filter { $0 != wolfName! }
    for name in nonWolves {
      #expect(state.variables["assigned_\(name)"] == "りんご")
    }
  }

  @Test func emitsAssignmentEvents() async throws {
    let mock = MockLLMService(responses: [])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      phases: [Phase(type: .assign, source: "topics", target: .all)],
      extraData: ["topics": .array(["Topic"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.currentRound = 1
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let assignments = collector.events.compactMap { event -> String? in
      if case .assignment(let agent, _) = event { return agent }
      return nil
    }
    #expect(assignments.count == 2)
    #expect(assignments.contains("Alice"))
    #expect(assignments.contains("Bob"))
  }
}
