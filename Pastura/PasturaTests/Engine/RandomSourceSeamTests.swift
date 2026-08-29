import Foundation
import Testing

@testable import Pastura

/// Pins the ADR-023 S3b RNG seam's *reach*: a ``RandomSource`` injected at the
/// ``SimulationRunner`` / ``PhaseContext`` boundary must actually drive every
/// draw the Engine makes, so a cross-language parity fixture handing both
/// engines the same seed gets the same `assign random_one` / `event_inject`
/// outcomes. `RandomSourceTests` pins the generator itself; this suite pins
/// the wiring around it.
///
/// Every expected index below is derived by hand from the SplitMix64
/// known-answer vectors in `RandomSourceTests` — the seam's reductions are
/// `index(below: n) == nextUInt64() % n` and `unit() == (bits >> 11) * 2^-53`,
/// so the literals here are checkable without running the code.
///
/// Serialized: the runner cases create Tasks and AsyncStreams that interfere
/// with each other when run in parallel on the simulator.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct RandomSourceSeamTests {
  /// `assign random_one` draws the topic first, then the wolf — so with
  /// `SplitMix64RandomSource(seed: 0)` (raw stream `0xE220A8397B1DCDAF`,
  /// `0x6E789E6AA1B965F4`, …) the picks are:
  ///
  /// - topic: `0xE220A8397B1DCDAF % 2 == 1` → the second topic (`"みかん"` pair)
  /// - wolf:  `0x6E789E6AA1B965F4 % 3 == 0` → `Alice`
  ///
  /// Same seed twice ⇒ identical `.assignment` events; that is the property a
  /// parity fixture depends on.
  @Test func seededAssignRandomOneIsDeterministic() async throws {
    let first = try await runAssignRandomOne(seed: 0)
    let second = try await runAssignRandomOne(seed: 0)

    #expect(first == second)
    #expect(first.wolfName == "Alice")
    #expect(first.assignments["Alice"] == "みかん")
    #expect(first.assignments["Bob"] == "りんご")
    #expect(first.assignments["Charlie"] == "りんご")
  }

  /// A different seed picks a different topic *and* a different wolf, so the
  /// assertion above cannot pass by accident on a seam that ignores the
  /// injected source. Seed 2's first two draws reduce to `% 2 == 0` (the first
  /// topic, the `"ぶどう"` pair) and `% 3 == 2` (`Charlie`).
  @Test func differentSeedPicksDifferentTopicAndWolf() async throws {
    let result = try await runAssignRandomOne(seed: 2)

    #expect(result.wolfName == "Charlie")
    #expect(result.assignments["Charlie"] == "ぶどう(minority)")
    #expect(result.assignments["Alice"] == "ぶどう")
    #expect(result.assignments["Bob"] == "ぶどう")
  }

  /// The Critical case: an `event_inject` nested inside a `conditional` branch
  /// must see the *injected* source. `ConditionalHandler` builds a fresh
  /// sub-``PhaseContext``, and omitting `random:` there silently reverts the
  /// sub-phase to the system RNG — this run would then fire (or not) at random.
  ///
  /// Seed 3's stream reduces to `unit() == 0.113450…` (< the phase's `0.5`, so
  /// the roll hits) and then `% 2 == 1` for the pick, i.e. the second event.
  @Test func seededEventInjectInsideConditionalFires() async throws {
    let injected = try await runConditionalEventInject(seed: 3)
    #expect(injected == ["停電"])
  }

  /// The paired miss: seed 0's first `unit()` is `0.883310…`, which is not
  /// `< 0.5`, so the same scenario injects nothing. Together with the case
  /// above this pins both sides of the roll to the injected stream.
  @Test func seededEventInjectInsideConditionalMisses() async throws {
    let injected = try await runConditionalEventInject(seed: 0)
    #expect(injected == [])
  }

  /// Behaviour preservation: a runner built without `random:` still runs
  /// `assign random_one` and produces a well-formed assignment. The default is
  /// ``SystemRandomSource``, so only the *shape* is assertable here — that is
  /// the point, since shipped behaviour must be unchanged by the seam.
  @Test func defaultRandomSourceStillAssigns() async throws {
    let scenario = makeWordWolfScenario()
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let runner = SimulationRunner()
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    var assignments: [String: String] = [:]
    for event in events {
      if case .assignment(let agent, let value) = event { assignments[agent] = value }
    }
    #expect(assignments.count == 3)
    let minorities = assignments.values.filter { $0 == "みかん" || $0 == "ぶどう(minority)" }
    #expect(minorities.count == 1)
  }

  // MARK: - Fixtures

  /// Two grouped topics so the topic draw is observable, and three agents so
  /// the wolf draw is too. The second pair's majority/minority texts differ
  /// from the first's, so a single `.assignment` value identifies both draws.
  private func makeWordWolfScenario() -> Scenario {
    makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      language: "en",
      rounds: 1,
      phases: [Phase(type: .assign, source: "words", target: .randomOne)],
      extraData: [
        "words": .arrayOfDictionaries([
          ["majority": "ぶどう", "minority": "ぶどう(minority)"],
          ["majority": "りんご", "minority": "みかん"]
        ])
      ]
    )
  }

  private struct AssignOutcome: Equatable {
    let wolfName: String?
    let assignments: [String: String]
  }

  /// Drives `assign random_one` through a full ``SimulationRunner`` so the
  /// runner → ``PhaseContext`` leg of the seam is covered, not just the helper.
  private func runAssignRandomOne(seed: UInt64) async throws -> AssignOutcome {
    let scenario = makeWordWolfScenario()
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let runner = SimulationRunner(random: SplitMix64RandomSource(seed: seed))
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    var assignments: [String: String] = [:]
    for event in events {
      if case .assignment(let agent, let value) = event { assignments[agent] = value }
    }
    // `wolf_name` lives in state, which the event stream does not carry, so
    // derive it from the one agent holding a minority value.
    let wolf = assignments.first { $0.value == "みかん" || $0.value == "ぶどう(minority)" }
    return AssignOutcome(wolfName: wolf?.key, assignments: assignments)
  }

  /// Runs an `event_inject` nested one level inside a `conditional` whose
  /// condition always holds, and returns the non-`nil` injected event texts.
  private func runConditionalEventInject(seed: UInt64) async throws -> [String] {
    let scenario = makeTestScenario(
      // Two agents: `ScenarioValidator` rejects a single-agent scenario
      // ("Agent count (1) is below minimum of 2") before the run starts.
      agentNames: ["Alice", "Bob"],
      language: "en",
      rounds: 1,
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round >= 1",
          thenPhases: [
            Phase(type: .eventInject, source: "events", probability: 0.5)
          ]
        )
      ],
      extraData: ["events": .array(["大雨", "停電"])]
    )
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let runner = SimulationRunner(random: SplitMix64RandomSource(seed: seed))
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    var injected: [String] = []
    for event in events {
      if case .eventInjected(let value) = event, let value { injected.append(value) }
    }
    return injected
  }
}
