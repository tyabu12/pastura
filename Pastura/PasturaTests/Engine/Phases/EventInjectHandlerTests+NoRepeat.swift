import Foundation
import Testing

@testable import Pastura

/// `no_repeat` draw-without-replacement tests for `EventInjectHandler` (#1006).
///
/// Sibling extension of `EventInjectHandlerTests` (NOT a new `@Suite`) so the
/// no_repeat cases share the parent suite's `.serialized`-free parallel run and
/// its `handler` / `injectedEvents` / `favoredKey` helpers — split out only to
/// keep the main file under swiftlint's 400-line `file_length` cap (see
/// `.claude/rules/testing.md` § "Splitting a Suite Across Files").
///
/// Determinism follows the parent suite's pattern: a 2-element source with one
/// entry pre-seeded as drawn leaves a 1-element remainder, so `randomElement()`
/// is deterministic without RNG injection; the exhausted-pool reset asserts on
/// set cardinality (deterministic) rather than which element is redrawn.
extension EventInjectHandlerTests {

  // MARK: - Draw without replacement

  @Test func noRepeatDrawsFromRemainder() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .eventInject, source: "events", probability: 1.0, noRepeat: true)],
      extraData: ["events": .array(["A", "B"])]
    )
    var state = SimulationState.initial(for: scenario)
    // "A" already drawn → only "B" remains, so the pick is deterministic.
    state.drawnEvents["current_event"] = ["A"]
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "B")
    // The chosen entry joins the drawn-set for the run.
    #expect(state.drawnEvents["current_event"] == ["A", "B"])
    #expect(injectedEvents(collector) == ["B"])
  }

  @Test func noRepeatExhaustedPoolResetsAndDraws() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .eventInject, source: "events", probability: 1.0, noRepeat: true)],
      extraData: ["events": .array(["A", "B"])]
    )
    var state = SimulationState.initial(for: scenario)
    // Both entries drawn → the remainder is empty, forcing a reset+redraw.
    state.drawnEvents["current_event"] = ["A", "B"]
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    // A miss would blank the variable; instead we reset and redraw a real event.
    let chosen = try #require(state.variables["current_event"])
    #expect(["A", "B"].contains(chosen))
    // Reset clears the pool, then adds only the freshly-redrawn entry.
    #expect(state.drawnEvents["current_event"] == [chosen])
  }

  @Test func noRepeatSingleElementRedrawsAfterReset() async throws {
    // One-element pool: every round exhausts and resets, so the same event is
    // redrawn deterministically and the drawn-set never grows past 1.
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .eventInject, source: "events", probability: 1.0, noRepeat: true)],
      extraData: ["events": .array(["only"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])

    for _ in 0..<3 {
      let collector = EventCollector()
      let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
      try await handler.execute(context: context, state: &state)
      #expect(state.variables["current_event"] == "only")
      #expect(state.drawnEvents["current_event"] == ["only"])
    }
  }

  // MARK: - Default path unaffected

  @Test func defaultKeepsWithReplacementAndNeverTouchesDrawnEvents() async throws {
    // no_repeat absent → existing randomElement() path, drawnEvents untouched.
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .eventInject, source: "events", probability: 1.0)],
      extraData: ["events": .array(["A"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "A")
    #expect(state.drawnEvents.isEmpty)
  }

  // MARK: - Custom variable name keys the drawn-set

  @Test func noRepeatHonorsCustomVariableName() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [
        Phase(
          type: .eventInject, source: "events", probability: 1.0,
          eventVariable: "my_event", noRepeat: true)
      ],
      extraData: ["events": .array(["A", "B"])]
    )
    var state = SimulationState.initial(for: scenario)
    state.drawnEvents["my_event"] = ["A"]
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["my_event"] == "B")
    #expect(state.drawnEvents["my_event"] == ["A", "B"])
    // Default key is never used when `as:` is set.
    #expect(state.drawnEvents["current_event"] == nil)
  }

  // MARK: - Dict-shaped source preserves the companion favored variable (#931)

  @Test func noRepeatDictSourcePreservesFavoredVariable() async throws {
    // The no_repeat branch must funnel the chosen (text, favors) tuple through
    // the same `__favors` write as the default path — else event_reactive
    // scoring silently breaks for dict-shaped no_repeat scenarios.
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .eventInject, source: "events", probability: 1.0, noRepeat: true)],
      extraData: [
        "events": .arrayOfDictionaries([
          ["text": "A", "favors": "betray"],
          ["text": "B", "favors": "cooperate"]
        ])
      ]
    )
    var state = SimulationState.initial(for: scenario)
    state.drawnEvents["current_event"] = ["A"]  // only "B" remains
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "B")
    #expect(state.variables[favoredKey()] == "cooperate")
    #expect(state.drawnEvents["current_event"] == ["A", "B"])
  }

  // MARK: - A miss does not consume the pool

  @Test func noRepeatMissDoesNotConsumePool() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice"],
      phases: [Phase(type: .eventInject, source: "events", probability: 0.0, noRepeat: true)],
      extraData: ["events": .array(["A", "B"])]
    )
    var state = SimulationState.initial(for: scenario)
    let mock = MockLLMService(responses: [])
    let collector = EventCollector()

    let context = makePhaseContext(scenario: scenario, llm: mock, collector: collector)
    try await handler.execute(context: context, state: &state)

    #expect(state.variables["current_event"] == "")
    // A probability miss injects nothing, so it must not mark anything drawn.
    #expect(state.drawnEvents.isEmpty)
    #expect(injectedEvents(collector) == [nil])
  }
}
