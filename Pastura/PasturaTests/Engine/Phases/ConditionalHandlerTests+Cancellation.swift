import Foundation
import Testing
import os

@testable import Pastura

/// Cancellation tail of a `conditional` branch (ADR-023 S4, #1622).
///
/// Invariant, matched to the Kotlin engine: a branch cut short by cancellation
/// aborts by throwing ``SimulationError/cancelled`` rather than returning
/// normally. That is what keeps the run's tail to exactly one
/// `.error(.cancelled)` — the runner's `catch` emits it — with no
/// `.phaseCompleted(.conditional)` for the branch that never finished and no
/// `.simulationCompleted` after a cancel. A silent return produced all three
/// defects, and on the pause path a second `.error(.cancelled)` as well.
///
/// The runner-side half of the invariant is asserted indirectly here: events
/// emitted after cancellation are unobservable through
/// `SimulationRunner.run`'s `AsyncStream` (cancelling the consumer terminates
/// the stream, which is what cancels the runner's task in the first place), so
/// the contract is pinned at the handler boundary where it is deterministic.
extension ConditionalHandlerTests {

  // MARK: - `Task.isCancelled` poll between sub-phases

  @Test func cancellationBetweenSubPhasesThrowsCancelled() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 0",
      thenPhases: [
        Phase(type: .summarize, template: "s0"),
        Phase(type: .summarize, template: "s1")
      ]
    )
    let collector = EventCollector()
    let mock = MockLLMService(responses: [])

    // The first sub-phase's pause check signals that it was reached, parks
    // until the task is cancelled, and then reports "not paused". Sub-phase 0
    // therefore runs to completion and the loop head for sub-phase 1 is
    // reached with cancellation already pending — the `Task.isCancelled` poll,
    // not the pause path. Cancelling before the handler starts would instead
    // trip the poll at index 0, so the flag is what makes this deterministic.
    let reachedFirstPauseCheck = OSAllocatedUnfairLock(initialState: false)
    let context = makeCancellationContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector,
      pauseCheck: { path in
        if path == [0, 0] {
          reachedFirstPauseCheck.withLock { $0 = true }
          while !Task.isCancelled { await Task.yield() }
        }
        return false
      }
    )

    let task = Task<Void, Error> {
      var state = SimulationState.initial(for: scenario)
      try await ConditionalHandler().execute(context: context, state: &state)
    }
    while !reachedFirstPauseCheck.withLock({ $0 }) { await Task.yield() }
    task.cancel()

    await #expect(throws: SimulationError.cancelled) { try await task.value }

    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.contains("s0"))
    #expect(!summaries.contains("s1"))

    // The completed sub-phase stays paired; the abandoned one never started.
    #expect(completedPaths(collector) == [[0, 0]])
    #expect(startedPaths(collector) == [[0, 0]])
  }

  // MARK: - Cancelled while parked on a pause between sub-phases

  @Test func pauseCheckCancellationThrowsCancelledWithoutEmittingError() async throws {
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"])
    let conditional = Phase(
      type: .conditional,
      condition: "current_round == 0",
      thenPhases: [
        Phase(type: .summarize, template: "s0"),
        Phase(type: .summarize, template: "s1")
      ]
    )
    var state = SimulationState.initial(for: scenario)
    let collector = EventCollector()
    let mock = MockLLMService(responses: [])

    // `true` == "cancelled while paused" — the runner's contract obliges the
    // handler to throw, and to leave the single `.error(.cancelled)` to the
    // runner.
    let context = makeCancellationContext(
      scenario: scenario, phase: conditional, llm: mock, collector: collector,
      pauseCheck: { path in path == [0, 1] }
    )

    await #expect(throws: SimulationError.cancelled) {
      try await ConditionalHandler().execute(context: context, state: &state)
    }

    let errors = collector.events.filter {
      if case .error = $0 { return true }
      return false
    }
    #expect(errors.isEmpty)
    #expect(completedPaths(collector) == [[0, 0]])
  }
}

/// Builds a top-level (`[0]`) conditional context with an explicit pause hook.
///
/// A sibling-file mirror of the suite's own `makeContext`, which is `private`
/// (file-scoped) and therefore unreachable from this extension.
private func makeCancellationContext(
  scenario: Scenario,
  phase: Phase,
  llm: LLMService,
  collector: EventCollector,
  pauseCheck: @escaping @Sendable (_ phasePath: [Int]) async -> Bool
) -> PhaseContext {
  PhaseContext(
    scenario: scenario,
    phase: phase,
    llm: llm,
    suspendController: SuspendController(),
    emitter: collector.emit,
    pauseCheck: pauseCheck,
    phasePath: [0],
    turnGate: TurnFailureGate()
  )
}

private func startedPaths(_ collector: EventCollector) -> [[Int]] {
  collector.events.compactMap { event in
    if case .phaseStarted(_, let path) = event { return path }
    return nil
  }
}

private func completedPaths(_ collector: EventCollector) -> [[Int]] {
  collector.events.compactMap { event in
    if case .phaseCompleted(_, let path) = event { return path }
    return nil
  }
}
