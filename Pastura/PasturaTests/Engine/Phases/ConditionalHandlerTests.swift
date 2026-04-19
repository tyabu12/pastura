import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ConditionalHandlerTests {
  let handler = ConditionalHandler()

  private func makeContext(
    scenario: Scenario,
    phase: Phase,
    llm: LLMService,
    collector: EventCollector,
    pauseCheck: @escaping @Sendable (_ phasePath: [Int]) async -> Bool = { _ in false }
  ) -> PhaseContext {
    // Top-level conditional phases run at path [0] in these tests — tests
    // that care about paths assert against `[0, N]` for sub-phases.
    PhaseContext(
      scenario: scenario,
      phase: phase,
      llm: llm,
      suspendController: SuspendController(),
      emitter: collector.emit,
      pauseCheck: pauseCheck,
      phasePath: [0]
    )
  }

  // MARK: - Branch selection

  @Test func trueConditionRunsThenBranch() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let thenPhase = Phase(type: .summarize, template: "then-branch")
    let elsePhase = Phase(type: .summarize, template: "else-branch")
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 0",
      thenPhases: [thenPhase],
      elsePhases: [elsePhase]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("then-branch"))
    #expect(!summaries.contains("else-branch"))
  }

  @Test func falseConditionRunsElseBranch() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let thenPhase = Phase(type: .summarize, template: "then-branch")
    let elsePhase = Phase(type: .summarize, template: "else-branch")
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 99",
      thenPhases: [thenPhase],
      elsePhases: [elsePhase]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("else-branch"))
    #expect(!summaries.contains("then-branch"))
  }

  // MARK: - conditionalEvaluated event

  @Test func emitsConditionalEvaluatedEvent() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    var state = SimulationState.initial(for: scenario)
    state.scores = ["Alice": 5, "Bob": 1]
    let conditional = Phase(
      type: .conditional,
      condition: "max_score >= 5",
      thenPhases: []
    )
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let events = collector.events.compactMap { event -> (String, Bool)? in
      if case .conditionalEvaluated(let cond, let result) = event { return (cond, result) }
      return nil
    }
    #expect(events.count == 1)
    #expect(events[0].0 == "max_score >= 5")
    #expect(events[0].1 == true)
  }

  // MARK: - Nested phasePath

  @Test func nestedPhaseStartedCarriesNestedPath() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let sub0 = Phase(type: .summarize, template: "s0")
    let sub1 = Phase(type: .summarize, template: "s1")
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 0",
      thenPhases: [sub0, sub1]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let startedPaths = collector.events.compactMap { event -> [Int]? in
      if case .phaseStarted(_, let path) = event { return path }
      return nil
    }
    // Top-level conditional's own `.phaseStarted` is emitted by
    // `SimulationRunner`, not by this handler — so only nested starts
    // appear in the collector for this unit test.
    #expect(startedPaths == [[0, 0], [0, 1]])
  }

  // MARK: - Runtime-absent → .summary warning

  @Test func runtimeAbsentVariableEmitsWarning() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let conditional = Phase(
      type: .conditional,
      condition: "vote_winner == \"Alice\"",
      thenPhases: [],
      elsePhases: []
    )
    var state = SimulationState.initial(for: scenario)  // empty voteResults
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    let warningTexts = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event, text.contains("vote_winner") { return text }
      return nil
    }
    #expect(!warningTexts.isEmpty)

    // Still emits conditionalEvaluated with result=false
    let conditionalEvents = collector.events.compactMap { event -> Bool? in
      if case .conditionalEvaluated(_, let result) = event { return result }
      return nil
    }
    #expect(conditionalEvents == [false])
  }

  // MARK: - Empty branch is a no-op

  @Test func emptyThenBranchIsNoOp() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 0",
      thenPhases: [],
      elsePhases: []
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // No sub-phase lifecycle events at all.
    let startedEvents = collector.events.filter {
      if case .phaseStarted = $0 { return true }
      return false
    }
    #expect(startedEvents.isEmpty)
  }

  // MARK: - pauseCheck honored between sub-phases

  @Test func pauseCheckStopsBranchExecution() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let sub0 = Phase(type: .summarize, template: "s0")
    let sub1 = Phase(type: .summarize, template: "s1")
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 0",
      thenPhases: [sub0, sub1]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    // pauseCheck returns true on the second sub-phase → handler returns
    // early before executing sub1.
    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector,
      pauseCheck: { path in path == [0, 1] }
    )
    try await handler.execute(context: context, state: &state)

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("s0"))
    #expect(!summaries.contains("s1"))
  }

  // MARK: - Malformed condition throws

  @Test func missingConditionThrowsFromEvaluator() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let conditional = Phase(
      type: .conditional,
      condition: "max_score",  // no operator
      thenPhases: [Phase(type: .summarize, template: "then")]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makeContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector)
    await #expect(throws: SimulationError.self) {
      try await handler.execute(context: context, state: &state)
    }
  }
}
