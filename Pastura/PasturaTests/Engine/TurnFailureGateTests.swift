import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct TurnFailureGateTests {
  private func skippedEvents(_ collector: EventCollector) -> [SimulationEvent] {
    collector.events.filter {
      if case .turnSkipped = $0 { return true }
      return false
    }
  }

  @Test func successReturnsValueAndEmitsNothing() async throws {
    let gate = TurnFailureGate()
    let collector = EventCollector()

    let value = try await gate.attempt(
      agent: "Alice", phaseType: .speakAll, emitter: collector.emit
    ) { "ok" }

    #expect(value == "ok")
    #expect(collector.events.isEmpty)
  }

  @Test func transientFailureSkipsTurnAndEmitsTurnSkipped() async throws {
    let gate = TurnFailureGate()
    let collector = EventCollector()

    let value: String? = try await gate.attempt(
      agent: "Alice", phaseType: .speakAll, emitter: collector.emit
    ) { throw SimulationError.retriesExhausted }

    #expect(value == nil)
    #expect(
      skippedEvents(collector) == [
        .turnSkipped(agent: "Alice", phaseType: .speakAll, cause: "retries exhausted")
      ])
  }

  @Test func generationFailureCarriesDescriptionAsCause() async throws {
    let gate = TurnFailureGate()
    let collector = EventCollector()

    let value: String? = try await gate.attempt(
      agent: "Bob", phaseType: .vote, emitter: collector.emit
    ) { throw SimulationError.llmGenerationFailed(description: "transient blip") }

    #expect(value == nil)
    #expect(
      skippedEvents(collector) == [
        .turnSkipped(agent: "Bob", phaseType: .vote, cause: "transient blip")
      ])
  }

  @Test func systemicErrorRethrowsTypedWithoutSkip() async throws {
    // ADR-021 D3: a deterministic engineering bug must abort in one throw,
    // not degrade turn-by-turn.
    let gate = TurnFailureGate()
    let collector = EventCollector()

    await #expect(throws: LLMError.invalidGrammar(description: "boom")) {
      _ = try await gate.attempt(
        agent: "Alice", phaseType: .speakAll, emitter: collector.emit
      ) { throw LLMError.invalidGrammar(description: "boom") }
    }
    #expect(collector.events.isEmpty)
  }

  @Test func cancellationRethrowsWithoutSkip() async throws {
    // ADR-021 D3 control-flow class: user cancellation must never be
    // converted into a skipped turn.
    let gate = TurnFailureGate()
    let collector = EventCollector()

    await #expect(throws: CancellationError.self) {
      _ = try await gate.attempt(
        agent: "Alice", phaseType: .speakAll, emitter: collector.emit
      ) { throw CancellationError() }
    }
    #expect(collector.events.isEmpty)
  }

  @Test func thirdConsecutiveFailureTripsBreaker() async throws {
    // ADR-021 D4: skips 1 and 2 emit .turnSkipped; the 3rd consecutive
    // failure throws turnFailureLimitReached INSTEAD of a 3rd skip. The
    // counter is shared across phases — the failures span speak_all → vote.
    let gate = TurnFailureGate()
    let collector = EventCollector()

    for phase in [PhaseType.speakAll, .speakAll] {
      let value: String? = try await gate.attempt(
        agent: "Alice", phaseType: phase, emitter: collector.emit
      ) { throw SimulationError.retriesExhausted }
      #expect(value == nil)
    }

    await #expect(throws: SimulationError.turnFailureLimitReached(consecutiveCount: 3)) {
      _ = try await gate.attempt(
        agent: "Bob", phaseType: .vote, emitter: collector.emit
      ) { throw SimulationError.retriesExhausted }
    }
    // Only the first two failures produced skip events.
    #expect(skippedEvents(collector).count == 2)
  }

  @Test func successResetsConsecutiveCounter() async throws {
    // ADR-021 D4: F F S F F must NOT trip the 3-consecutive breaker.
    let gate = TurnFailureGate()
    let collector = EventCollector()

    func fail() async throws -> String? {
      try await gate.attempt(
        agent: "Alice", phaseType: .speakAll, emitter: collector.emit
      ) { throw SimulationError.retriesExhausted }
    }

    _ = try await fail()
    _ = try await fail()
    let ok = try await gate.attempt(
      agent: "Alice", phaseType: .speakAll, emitter: collector.emit
    ) { "recovered" }
    #expect(ok == "recovered")
    _ = try await fail()
    _ = try await fail()

    #expect(skippedEvents(collector).count == 4)
  }
}
