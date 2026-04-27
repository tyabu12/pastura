import Foundation
import Testing

@testable import Pastura

/// Unit tests for `EventInjectHandler`.
///
/// `RandomNumberGenerator` injection is intentionally avoided per the
/// project pattern set by `AssignHandler` — boundary probabilities
/// (0.0 / 1.0) and single-element source arrays make every assertion
/// here deterministic without RNG mocks.
@Suite(.timeLimit(.minutes(1)))
struct EventInjectHandlerTests {
  let handler = EventInjectHandler()

  /// Extracts every `.eventInjected(event:)` payload from a collector,
  /// preserving `nil` payloads. Manual loop instead of `compactMap` —
  /// `compactMap { _ -> String? in ... }` would silently drop the
  /// "miss" cases (`.eventInjected(nil)`) that we want to assert on.
  private func injectedEvents(_ collector: EventCollector) -> [String?] {
    var result: [String?] = []
    for event in collector.events {
      if case .eventInjected(let value) = event {
        result.append(value)
      }
    }
    return result
  }

  // MARK: - Probability boundaries

  @Test func firesWhenProbabilityIsOne() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .eventInject, source: "events", probability: 1.0)
      ],
      extraData: ["events": .array(["突然停電"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "突然停電")
    #expect(injectedEvents(collector) == ["突然停電"])
  }

  @Test func missesWhenProbabilityIsZero() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .eventInject, source: "events", probability: 0.0)
      ],
      extraData: ["events": .array(["突然停電"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // Empty-string write (not absent) so prompts that reference
    // {current_event} expand cleanly without ghosting last round's value.
    #expect(state.variables["current_event"] == "")
    #expect(injectedEvents(collector) == [nil])
  }

  // MARK: - Default probability

  @Test func defaultProbabilityFires() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .eventInject, source: "events")  // probability nil → 1.0
      ],
      extraData: ["events": .array(["only"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "only")
  }

  // MARK: - Custom variable name (`as:`)

  @Test func customVariableNameOverridesDefault() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(
          type: .eventInject,
          source: "events", probability: 1.0,
          eventVariable: "my_event")
      ],
      extraData: ["events": .array(["x"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["my_event"] == "x")
    // Default key untouched.
    #expect(state.variables["current_event"] == nil)
  }

  // MARK: - Source-missing / empty

  @Test func missingSourceEmitsWarningAndMissesCleanly() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .eventInject, source: "nonexistent", probability: 1.0)
      ]
      // extraData empty — source key absent
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "")
    #expect(injectedEvents(collector) == [nil])

    let warningContainsKey = collector.events.contains { event in
      if case .summary(let text) = event, text.contains("nonexistent") { return true }
      return false
    }
    #expect(warningContainsKey)
  }

  @Test func emptyArrayBehavesLikeMiss() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .eventInject, source: "events", probability: 1.0)
      ],
      extraData: ["events": .array([])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "")
    #expect(injectedEvents(collector) == [nil])
  }

  // MARK: - Single-element source determinism (no RNG injection needed)

  @Test func singleElementSourceIsDeterministic() async throws {
    // Multiple invocations with the same scenario MUST produce the same
    // injected value — `randomElement()` on a one-element array is
    // deterministic, mirroring the AssignHandler test pattern.
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(type: .eventInject, source: "events", probability: 1.0)
      ],
      extraData: ["events": .array(["only"])]
    )
    let mock = MockLLMService(responses: [])

    for _ in 0..<5 {
      var state = SimulationState.initial(for: scenario)
      let collector = EventCollector()
      let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
      try await handler.execute(context: context, state: &state)
      #expect(state.variables["current_event"] == "only")
    }
  }

  // MARK: - Default variable name constant

  @Test func defaultVariableNameMatchesPhaseDocumentation() {
    // The Phase doc-comment + editor footer + this constant must agree.
    // If you rename one, this test catches the divergence.
    #expect(EventInjectHandler.defaultVariableName == "current_event")
  }
}
