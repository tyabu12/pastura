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
/// **Kotlin twin: `shared/engine/src/commonTest/.../RandomSourceSeamTests.kt`.**
/// Same scenarios, same seeds, SAME expected sequences — a literal that diverges
/// between the two files is a parity break even when both suites are green.
///
/// Every expectation below is derived by hand from the SplitMix64 known-answer
/// vectors in `RandomSourceTests` — the seam's reductions are
/// `index(below: n) == nextUInt64() % n` and `unit() == (bits >> 11) * 2^-53`,
/// so the literals here are checkable without running the code. Each case's
/// doc comment carries its own derivation.
///
/// **Why full ORDERED sequences rather than one pick.** A single-round
/// assertion over a 2-topic pool passes 1 time in 2 for a seam that silently
/// fell back to the system RNG — most of all in `ConditionalHandler`, where
/// dropping `random: context.random` from the sub-context reverts only the
/// nested phase. Asserting several rounds of an 8-wide draw puts the
/// false-pass rate at 8⁻³ ≈ 0.2%, which is the difference between a regression
/// guard and a coin flip.
///
/// Serialized: the runner cases create Tasks and AsyncStreams that interfere
/// with each other when run in parallel on the simulator.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct RandomSourceSeamTests {
  /// `assign random_one` draws the topic first, then the wolf, once per round —
  /// so over three rounds with `SplitMix64RandomSource(seed: 0)` (raw stream
  /// `0xE220A8397B1DCDAF`, `0x6E789E6AA1B965F4`, `0x06C45D188009454F`,
  /// `0xF88BB8A8724C81EC`, `0x1B39896A51A8749B`, `0x53CB9F0C747EA2EA`) the
  /// picks are:
  ///
  /// - round 1: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
  /// - round 2: `% 2 == 1` → the `"みかん"` pair; `% 3 == 1` → `Bob`
  /// - round 3: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
  ///
  /// Same seed twice ⇒ identical `.assignment` events; that is the property a
  /// parity fixture depends on.
  @Test func seededAssignRandomOneIsDeterministic() async throws {
    let first = try await runAssignRandomOne(seed: 0)
    let second = try await runAssignRandomOne(seed: 0)

    #expect(first == second)
    #expect(
      first == [
        RoundPick(minority: "みかん", wolf: "Alice"),
        RoundPick(minority: "みかん", wolf: "Bob"),
        RoundPick(minority: "みかん", wolf: "Alice")
      ])
  }

  /// A different seed picks a different topic *and* a different wolf, so the
  /// assertion above cannot pass by accident on a seam that ignores the
  /// injected source. Seed 2's stream is `0x975835DE1C9756CE`,
  /// `0xBFC846100BFC1E42`, `0x987BBCBFDD7E532F`, `0xC3F2827AFFE7F664`,
  /// `0x4FC446B53F17FB29`, `0x58BC3CB37BC7B2B3`, reducing to:
  ///
  /// - round 1: `% 2 == 0` → the `"ぶどう"` pair; `% 3 == 2` → `Charlie`
  /// - round 2: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
  /// - round 3: `% 2 == 1` → the `"みかん"` pair; `% 3 == 0` → `Alice`
  @Test func differentSeedPicksDifferentTopicAndWolf() async throws {
    let picks = try await runAssignRandomOne(seed: 2)

    #expect(
      picks == [
        RoundPick(minority: "ぶどう(minority)", wolf: "Charlie"),
        RoundPick(minority: "みかん", wolf: "Alice"),
        RoundPick(minority: "みかん", wolf: "Alice")
      ])
  }

  /// The critical case: an `event_inject` nested inside a `conditional` branch
  /// must see the *injected* source. `ConditionalHandler` builds a fresh
  /// sub-``PhaseContext``, and omitting `random:` there silently reverts the
  /// sub-phase to the system RNG.
  ///
  /// Eight distinct events over three rounds at `probability: 1.0`, so the
  /// whole ordered sequence is pinned and a seam that reverted to the system
  /// RNG false-passes at most 8⁻³. Each round draws twice: the roll (always
  /// `< 1.0`, so it never gates but is still consumed) and the pick. Seed 1's
  /// stream is `0x910A2DEC89025CC1`, `0xBEEB8DA1658EEC67`,
  /// `0xF893A2EEFB32555E`, `0x71C18690EE42C90B`, `0x71BB54D8D101B5B9`,
  /// `0xC34D0BFF90150280`, so the picks are the odd-indexed draws reduced
  /// `% 8`: `0x…67 % 8 == 7`, `0x…0B % 8 == 3`, `0x…80 % 8 == 0`.
  @Test func seededEventInjectInsideConditionalFires() async throws {
    let injected = try await runConditionalEventInject(
      seed: 1, events: (0..<8).map { "E\($0)" }, rounds: 3, probability: 1.0)

    #expect(injected == ["E7", "E3", "E0"])
  }

  /// The paired miss: seed 0's first `unit()` is `0.883310…`, which is not
  /// `< 0.5`, so the same scenario injects nothing. Together with the case
  /// above this pins both sides of the roll to the injected stream.
  @Test func seededEventInjectInsideConditionalMisses() async throws {
    let injected = try await runConditionalEventInject(
      seed: 0, events: ["大雨", "停電"], rounds: 1, probability: 0.5)

    #expect(injected == [])
  }

  /// `no_repeat: true` draws from the shrinking remainder and resets once the
  /// pool is exhausted, so the reset-path draw order is a cross-language
  /// contract of its own — a Kotlin/Swift disagreement about *when* the reset
  /// happens would only show from round 4 onwards.
  ///
  /// Pool `[N0, N1, N2]`, four rounds, `probability: 1.0` — two draws a round
  /// (roll, then pick over `remaining`). Seed 3's stream is
  /// `0x1D0B14E4DB018FED`, `0xB3466F8A7B81A989`, `0x9CEBE8A6D050DD01`,
  /// `0x12A764FB66ABC9CF`, `0x37688DADCAB79996`, `0xA2DF7737091F4F07`,
  /// `0x2298EB42CBBEFDB8`, `0xE3830D21DC859216`:
  ///
  /// - round 1: remainder `[N0, N1, N2]`, `0xB346… % 3 == 0` → `N0`
  /// - round 2: remainder `[N1, N2]`,     `0x12A7… % 2 == 1` → `N2`
  /// - round 3: remainder `[N1]`,         `0xA2DF… % 1 == 0` → `N1`
  /// - round 4: exhausted → reset to the full pool, `0xE383… % 3 == 1` → `N1`
  ///
  /// The first three are distinct (no-repeat holding) and the fourth repeats
  /// only because the reset draw genuinely lands there — a late repeat after
  /// exhaustion is the documented #1006 behaviour.
  @Test func seededNoRepeatDrawsAndResetsInStreamOrder() async throws {
    let injected = try await runConditionalEventInject(
      seed: 3, events: ["N0", "N1", "N2"], rounds: 4, probability: 1.0, noRepeat: true)

    #expect(injected == ["N0", "N2", "N1", "N1"])
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

    let rounds = assignmentRounds(in: events)
    #expect(rounds.count == 3)
    for round in rounds {
      #expect(round.count == 3)
      let minorities = round.filter { $0.value == "みかん" || $0.value == "ぶどう(minority)" }
      #expect(minorities.count == 1, "exactly one wolf, whatever the platform RNG picked")
    }
  }

  // MARK: - Fixtures

  /// Two grouped topics so the topic draw is observable, three agents so the
  /// wolf draw is too, and three rounds so the assertion is over a *sequence*.
  /// The second pair's majority/minority texts differ from the first's, so a
  /// single `.assignment` value identifies both draws.
  private func makeWordWolfScenario() -> Scenario {
    makeTestScenario(
      agentNames: ["Alice", "Bob", "Charlie"],
      language: "en",
      rounds: 3,
      phases: [Phase(type: .assign, source: "words", target: .randomOne)],
      extraData: [
        "words": .arrayOfDictionaries([
          ["majority": "ぶどう", "minority": "ぶどう(minority)"],
          ["majority": "りんご", "minority": "みかん"]
        ])
      ]
    )
  }

  /// One round's two draws, read back off the event stream: which topic pair
  /// the round drew (identified by its minority text) and which agent got it.
  private struct RoundPick: Equatable {
    let minority: String
    let wolf: String
  }

  /// Groups `.assignment` events into per-round chunks of one entry per active
  /// agent, preserving emission order within a round.
  private func assignmentRounds(in events: [SimulationEvent]) -> [[(agent: String, value: String)]] {
    var flat: [(agent: String, value: String)] = []
    for event in events {
      if case .assignment(let agent, let value) = event { flat.append((agent, value)) }
    }
    return stride(from: 0, to: flat.count, by: 3).map { Array(flat[$0..<min($0 + 3, flat.count)]) }
  }

  /// Drives `assign random_one` through a full ``SimulationRunner`` so the
  /// runner → ``PhaseContext`` leg of the seam is covered, not just the helper,
  /// and returns the per-round `(topic, wolf)` pair the run drew.
  private func runAssignRandomOne(seed: UInt64) async throws -> [RoundPick] {
    let scenario = makeWordWolfScenario()
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()

    let runner = SimulationRunner(random: SplitMix64RandomSource(seed: seed))
    let events = await collectAllEvents(
      runner.run(scenario: scenario, llm: mock, suspendController: SuspendController()))

    // `wolf_name` lives in state, which the event stream does not carry, so
    // derive it from the one agent holding a minority value each round.
    return assignmentRounds(in: events).compactMap { round in
      guard
        let wolf = round.first(where: {
          $0.value == "みかん" || $0.value == "ぶどう(minority)"
        })
      else { return nil }
      return RoundPick(minority: wolf.value, wolf: wolf.agent)
    }
  }

  /// Runs an `event_inject` nested one level inside a `conditional` whose
  /// condition always holds, and returns the non-`nil` injected event texts in
  /// emission order.
  private func runConditionalEventInject(
    seed: UInt64,
    events sourceEvents: [String],
    rounds: Int,
    probability: Double,
    noRepeat: Bool = false
  ) async throws -> [String] {
    let scenario = makeTestScenario(
      // Two agents: `ScenarioValidator` rejects a single-agent scenario
      // ("Agent count (1) is below minimum of 2") before the run starts.
      agentNames: ["Alice", "Bob"],
      language: "en",
      rounds: rounds,
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round >= 1",
          thenPhases: [
            Phase(
              type: .eventInject, source: "events", probability: probability,
              noRepeat: noRepeat ? true : nil)
          ]
        )
      ],
      extraData: ["events": .array(sourceEvents)]
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
