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
func makePhaseContext(
  scenario: Scenario,
  phaseIndex: Int = 0,
  llm: LLMService,
  collector: EventCollector
) -> PhaseContext {
  PhaseContext(
    scenario: scenario,
    phase: scenario.phases[phaseIndex],
    llm: llm,
    emitter: collector.emit
  )
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
