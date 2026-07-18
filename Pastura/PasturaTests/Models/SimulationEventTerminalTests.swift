import Testing

@testable import Pastura

/// Tests for `SimulationEvent.isTerminal` (#1171).
///
/// These pin the terminality of the cases that exist **today** — that
/// `.simulationCompleted` and `.error` stay terminal, and that their nearest
/// neighbours stay non-terminal.
///
/// What they deliberately do NOT cover, since it would be easy to read them as
/// covering it: a *newly added* case mis-assigned to the `false` arm. The
/// no-default `switch` forces a new case to make *a* decision, not the *right*
/// one, and a new case appears in none of the sample lists below, so nothing
/// here turns red either. Neither gate catches that; only review does. (Swift
/// enums with associated values cannot be `CaseIterable`, so there is no cheap
/// machinery to close it.)
///
/// `SimulationEventTerminalTests.kt` declares the same two terminal cases on
/// the Kotlin mirror. That agreement is maintained by hand — no gate compares
/// the two files.
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

  /// Of these ten sampled cases, exactly the two known terminals are terminal.
  ///
  /// `sample` is a fixed list, so this does not oblige a visit when a new case
  /// is added — it pins that the eight non-terminal neighbours stay that way,
  /// which is the direction a careless `true`-arm edit would break.
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
