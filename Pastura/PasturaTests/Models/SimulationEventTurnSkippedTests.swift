import Testing

@testable import Pastura

/// Tests for `SimulationEvent.turnSkipped` Equatable conformance
/// (ADR-021 D5). Mirrors `SimulationEventLanguageMismatchTests` — the
/// auto-synthesized Equatable on `SimulationEvent` carries the contract;
/// these pins guard against future associated-value reorders
/// (`(agent, phaseType, cause)`) silently flipping equality.
@Suite(.timeLimit(.minutes(1)))
struct SimulationEventTurnSkippedTests {
  @Test func equalCases() {
    let lhs = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "generation timeout")
    let rhs = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "generation timeout")
    #expect(lhs == rhs)
  }

  @Test func differentAgentNotEqual() {
    let alice = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "generation timeout")
    let bob = SimulationEvent.turnSkipped(
      agent: "Bob", phaseType: .speakAll, cause: "generation timeout")
    #expect(alice != bob)
  }

  @Test func differentPhaseTypeNotEqual() {
    let speak = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "generation timeout")
    let vote = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .vote, cause: "generation timeout")
    #expect(speak != vote)
  }

  @Test func differentCauseNotEqual() {
    let timeout = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "generation timeout")
    let parseFailed = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "retries exhausted")
    #expect(timeout != parseFailed)
  }

  @Test func notEqualToDifferentCase() {
    let skipped = SimulationEvent.turnSkipped(
      agent: "Alice", phaseType: .speakAll, cause: "generation timeout")
    let started = SimulationEvent.inferenceStarted(agent: "Alice")
    #expect(skipped != started)
  }
}
