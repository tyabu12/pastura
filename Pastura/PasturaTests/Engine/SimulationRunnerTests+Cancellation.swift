import Foundation
import Testing
import os

@testable import Pastura

/// Cancellation tail of a run (ADR-023 S4, #1622), matched to the Kotlin engine:
/// every cancellation path emits **exactly one** `.error(.cancelled)` and it is
/// the last event; `.simulationCompleted` never follows a cancel; and a
/// `conditional` branch cut short emits no outer
/// `.phaseCompleted(.conditional, [k])` — the sub-phases that did finish keep
/// their `[k, n]` pairs.
///
/// These drive the `emitter:` overload of `run`, not the `AsyncStream` one: the
/// stream's only cancel path is terminating the stream, which drops everything
/// emitted afterwards, so the tail under test would be invisible there.
///
/// Each case cancels from inside the emitter — it runs synchronously on the
/// run's own task, so cancellation is already pending when the runner reaches
/// its next check. That is what makes the cut point exact instead of a sleep.
extension SimulationRunnerTests {

  // MARK: - (a) Cancelled between sub-phases inside a branch

  @Test func cancelBetweenBranchSubPhasesEmitsSingleCancelledError() async throws {
    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#,
      #"{"statement": "hey"}"#
    ])
    try await mock.loadModel()

    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"]),
            Phase(type: .summarize, template: "s1")
          ]
        )
      ]
    )

    let runner = SimulationRunner()
    let collector = EventCollector()
    let box = RunTaskBox()

    // Cancel the instant the branch's first sub-phase completes — i.e. after
    // its last LLM call returned. The branch loop's next stop is the
    // `Task.isCancelled` poll at the head of sub-phase 1.
    let task = Task {
      await runner.run(
        scenario: scenario, llm: mock, suspendController: SuspendController(),
        emitter: { event in
          collector.emit(event)
          if case .phaseCompleted(_, let path) = event, path == [0, 0] { box.cancel() }
        })
    }
    box.arm(task)
    await task.value

    let events = collector.events
    expectSingleCancelledTail(events)
    #expect(completedPaths(events).contains([0, 0]))
    #expect(!completedPaths(events).contains([0]))

    // The abandoned sub-phase never ran.
    let summaries = events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(!summaries.contains("s1"))
  }

  // MARK: - (b) Cancelled while parked on a pause inside a branch

  @Test func cancelWhileParkedInsideBranchEmitsSingleCancelledError() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(
          type: .conditional,
          condition: "current_round == 1",
          thenPhases: [
            Phase(type: .summarize, template: "s0"),
            Phase(type: .summarize, template: "s1")
          ]
        )
      ]
    )

    let runner = SimulationRunner()
    let collector = EventCollector()
    let box = RunTaskBox()

    // Pause once the branch's first sub-phase is done, so the run parks at the
    // sub-phase-1 pause check; cancel it there. This is the path that used to
    // emit TWO `.error(.cancelled)` — one from `checkPaused`, one from the
    // round loop after the handler returned silently.
    let task = Task {
      await runner.run(
        scenario: scenario, llm: MockLLMService(responses: []),
        suspendController: SuspendController(),
        emitter: { event in
          collector.emit(event)
          switch event {
          case .phaseCompleted(_, let path) where path == [0, 0]:
            runner.isPaused = true
          case .simulationPaused(_, let path) where path == [0, 1]:
            box.cancel()
          default:
            break
          }
        })
    }
    box.arm(task)
    await task.value

    let events = collector.events
    expectSingleCancelledTail(events)
    #expect(completedPaths(events) == [[0, 0]])
  }

  // MARK: - (c) Cancelled while parked between top-level phases

  @Test func cancelWhileParkedBetweenTopLevelPhasesEmitsSingleCancelledError() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [
        Phase(type: .summarize, template: "p0"),
        Phase(type: .summarize, template: "p1")
      ]
    )

    let runner = SimulationRunner()
    let collector = EventCollector()
    let box = RunTaskBox()

    let task = Task {
      await runner.run(
        scenario: scenario, llm: MockLLMService(responses: []),
        suspendController: SuspendController(),
        emitter: { event in
          collector.emit(event)
          switch event {
          case .phaseCompleted(_, let path) where path == [0]:
            runner.isPaused = true
          case .simulationPaused(_, let path) where path == [1]:
            box.cancel()
          default:
            break
          }
        })
    }
    box.arm(task)
    await task.value

    let events = collector.events
    expectSingleCancelledTail(events)
    #expect(completedPaths(events) == [[0]])
  }

  // MARK: - (d) Cancelled while parked at the round-loop head

  @Test func cancelWhileParkedBetweenRoundsEmitsSingleCancelledError() async throws {
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 2,
      phases: [Phase(type: .summarize, template: "p0")]
    )

    let runner = SimulationRunner()
    let collector = EventCollector()
    let box = RunTaskBox()

    // Pause at the end of round 1 so the run parks at the round-2 loop head
    // (`phasePath: []`), then cancel it there.
    let task = Task {
      await runner.run(
        scenario: scenario, llm: MockLLMService(responses: []),
        suspendController: SuspendController(),
        emitter: { event in
          collector.emit(event)
          switch event {
          case .roundCompleted(1, _):
            runner.isPaused = true
          case .simulationPaused(2, let path) where path.isEmpty:
            box.cancel()
          default:
            break
          }
        })
    }
    box.arm(task)
    await task.value

    let events = collector.events
    expectSingleCancelledTail(events)
    let startedRounds = events.compactMap { event -> Int? in
      if case .roundStarted(let round, _) = event { return round }
      return nil
    }
    #expect(startedRounds == [1])
  }
}

/// Holds the run's `Task` so the emitter — which runs inside that very task —
/// can cancel it. `arm` is called synchronously right after `Task { }` returns,
/// before the test task ever suspends, so the box is always populated by the
/// time the run emits anything.
private final class RunTaskBox: @unchecked Sendable {
  private let stored = OSAllocatedUnfairLock(initialState: Task<Void, Never>?.none)

  func arm(_ task: Task<Void, Never>) {
    stored.withLock { $0 = task }
  }

  func cancel() {
    stored.withLock { $0 }?.cancel()
  }
}

/// The shared tail assertion: one `.error(.cancelled)`, last, and no
/// `.simulationCompleted` anywhere.
private func expectSingleCancelledTail(
  _ events: [SimulationEvent], sourceLocation: SourceLocation = #_sourceLocation
) {
  let errors = events.compactMap { event -> SimulationError? in
    if case .error(let error) = event { return error }
    return nil
  }
  #expect(errors == [.cancelled], sourceLocation: sourceLocation)

  if case .error(.cancelled)? = events.last {
    // Tail is the cancellation error, as required.
  } else {
    Issue.record(
      "expected `.error(.cancelled)` as the last event, got \(String(describing: events.last))",
      sourceLocation: sourceLocation)
  }

  #expect(
    !events.contains {
      if case .simulationCompleted = $0 { return true }
      return false
    }, sourceLocation: sourceLocation)
}

private func completedPaths(_ events: [SimulationEvent]) -> [[Int]] {
  events.compactMap { event in
    if case .phaseCompleted(_, let path) = event { return path }
    return nil
  }
}
