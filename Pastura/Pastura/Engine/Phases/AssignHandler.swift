import Foundation

/// Handles `assign` phases that distribute information to agents.
///
/// Supports two target modes:
/// - `"random_one"`: One random agent gets the minority value, rest get majority (word wolf).
/// - `"all"` (default): All agents get the same round-indexed item from the source array.
nonisolated struct AssignHandler: PhaseHandler {

  func execute(
    scenario: Scenario,
    phase: Phase,
    state: inout SimulationState,
    llm: LLMService,
    emitter: @Sendable (SimulationEvent) -> Void
  ) async throws {
    let sourceKey = phase.source ?? ""
    let target = phase.target ?? "all"
    let sourceData = scenario.extraData[sourceKey]

    let active = scenario.personas.filter { state.eliminated[$0.name] != true }

    if target == "random_one" {
      assignRandomOne(
        active: active, sourceData: sourceData, state: &state, emitter: emitter
      )
    } else {
      assignAll(
        active: active, sourceData: sourceData, state: &state, emitter: emitter
      )
    }
  }

  /// Assigns minority value to one random agent, majority to the rest.
  private func assignRandomOne(
    active: [Persona],
    sourceData: AnyCodableValue?,
    state: inout SimulationState,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    guard case .arrayOfDictionaries(let topics) = sourceData, !topics.isEmpty else {
      return
    }

    guard let topic = topics.randomElement() else { return }
    let wolfIdx = Int.random(in: 0..<active.count)

    for (index, persona) in active.enumerated() {
      if index == wolfIdx {
        let value = topic["minority"] ?? ""
        state.variables["assigned_\(persona.name)"] = value
        state.variables["wolf_name"] = persona.name
        emitter(.assignment(agent: persona.name, value: value))
      } else {
        let value = topic["majority"] ?? ""
        state.variables["assigned_\(persona.name)"] = value
        emitter(.assignment(agent: persona.name, value: value))
      }
    }
  }

  /// Assigns the same round-indexed item to all agents.
  private func assignAll(
    active: [Persona],
    sourceData: AnyCodableValue?,
    state: inout SimulationState,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    let item: String

    switch sourceData {
    case .array(let items) where !items.isEmpty:
      let roundIdx = (state.currentRound - 1) % items.count
      item = items[roundIdx]
    case .string(let str):
      item = str
    default:
      item = ""
    }

    state.variables["assigned_topic"] = item
    for persona in active {
      state.variables["assigned_\(persona.name)"] = item
      emitter(.assignment(agent: persona.name, value: item))
    }
  }
}
