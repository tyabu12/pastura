import Foundation
import os

@testable import Pastura

/// Thread-safe event collector for testing `@Sendable` emitter closures.
final class EventCollector: @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock(initialState: [SimulationEvent]())

  func emit(_ event: SimulationEvent) {
    lock.withLock { $0.append(event) }
  }

  var events: [SimulationEvent] {
    lock.withLock { $0 }
  }
}

/// Creates a ``PhaseContext`` for testing, bundling scenario, phase, LLM, and emitter.
///
/// `suspendController` defaults to a fresh, never-signalled instance so existing
/// handler tests don't need to opt into the suspend machinery. Tests that
/// exercise suspend/resume should pass an explicit controller.
///
/// The `phaseIndex` parameter is an array subscript into `scenario.phases` —
/// it is deliberately not renamed to match `SimulationEvent.phasePath` because
/// these are distinct concepts (a convenience index into the top-level phases
/// array vs. the structured path emitted in lifecycle events).
///
/// `pauseCheck` defaults to an always-false stub so handler unit tests don't
/// need to set up the pause machinery. Tests that exercise nested pause
/// semantics should pass an explicit closure.
func makePhaseContext(
  scenario: Scenario,
  phaseIndex: Int = 0,
  llm: LLMService,
  suspendController: SuspendController = SuspendController(),
  collector: EventCollector,
  pauseCheck: @escaping @Sendable (_ phasePath: [Int]) async -> Bool = { _ in false }
) -> PhaseContext {
  PhaseContext(
    scenario: scenario,
    phase: scenario.phases[phaseIndex],
    llm: llm,
    suspendController: suspendController,
    emitter: collector.emit,
    pauseCheck: pauseCheck
  )
}

/// Collects all events from an ``AsyncStream`` into an array.
///
/// Useful for integration and runner tests that consume `SimulationRunner.run()`.
func collectAllEvents(_ stream: AsyncStream<SimulationEvent>) async -> [SimulationEvent] {
  var events: [SimulationEvent] = []
  for await event in stream {
    events.append(event)
  }
  return events
}

/// Creates a minimal test scenario with the given agents and phases.
func makeTestScenario(
  agentNames: [String] = ["Alice", "Bob", "Charlie"],
  rounds: Int = 1,
  phases: [Phase] = [],
  context: String = "You are in a game.",
  extraData: [String: AnyCodableValue] = [:]
) -> Scenario {
  let personas = agentNames.map { Persona(name: $0, description: "A test persona for \($0)") }
  return Scenario(
    id: "test",
    name: "Test Scenario",
    description: "A test scenario",
    agentCount: agentNames.count,
    rounds: rounds,
    context: context,
    personas: personas,
    phases: phases,
    extraData: extraData
  )
}
