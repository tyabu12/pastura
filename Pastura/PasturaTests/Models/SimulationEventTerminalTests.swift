import Testing

@testable import Pastura

/// Tests for `SimulationEvent.isTerminal` (#1171).
///
/// The no-default `switch` behind the property forces a new case to make *a*
/// terminality decision, but not the *right* one: dropping a genuinely terminal
/// case into the `false` list compiles clean and silently reproduces the
/// never-finishing stream the property exists to prevent. These pins are the
/// half the compiler cannot cover.
///
/// Mirrored on the Kotlin side by `SimulationEventTerminalTests.kt` — the two
/// Models declarations must agree, and nothing else asserts that they do.
@Suite(.timeLimit(.minutes(1)))
struct SimulationEventTerminalTests {
  @Test func simulationCompletedIsTerminal() {
    #expect(SimulationEvent.simulationCompleted.isTerminal)
  }

  @Test func errorIsTerminal() {
    #expect(SimulationEvent.error(.cancelled).isTerminal)
    #expect(SimulationEvent.error(.retriesExhausted).isTerminal)
  }

  /// `.simulationPaused` is the trap this pins: a run stops after it, so it
  /// reads terminal, but the stream must stay open — a paused run resumes and
  /// keeps emitting. Treating it as terminal would truncate every resumed run.
  @Test func pausedIsNotTerminal() {
    #expect(!SimulationEvent.simulationPaused(round: 2, phasePath: [0]).isTerminal)
  }

  @Test func ordinaryEventsAreNotTerminal() {
    #expect(!SimulationEvent.roundStarted(round: 1, totalRounds: 3).isTerminal)
    #expect(!SimulationEvent.scoreUpdate(scores: ["Alice": 1]).isTerminal)
    #expect(!SimulationEvent.roundCheckpoint(state: .init(currentRound: 1)).isTerminal)
  }

  /// Exactly two cases are terminal. A future case added to the `true` arm
  /// widens stream termination for every consumer, so it should be a
  /// deliberate edit here rather than an incidental one.
  @Test func onlyTwoCasesAreTerminal() {
    let sample: [SimulationEvent] = [
      .roundStarted(round: 1, totalRounds: 1),
      .roundCompleted(round: 1, scores: [:]),
      .scoreUpdate(scores: [:]),
      .summary(text: "s"),
      .narration(text: "n"),
      .elimination(agent: "a", voteCount: 1),
      .simulationPaused(round: 1, phasePath: [0]),
      .inferenceStarted(agent: "a"),
      .simulationCompleted,
      .error(.cancelled)
    ]
    #expect(sample.filter(\.isTerminal).count == 2)
  }
}
