import Foundation

/// Handles `assign` phases that distribute information to agents.
///
/// Supports two target modes:
/// - `"random_one"`: One random agent gets the minority value, rest get majority (word wolf).
/// - `"all"` (default): All agents get the same round-indexed item from the source array.
nonisolated struct AssignHandler: PhaseHandler {

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let sourceKey = context.phase.source ?? ""
    let sourceData = context.scenario.extraData[sourceKey]

    let active = context.scenario.personas.filter { state.eliminated[$0.name] != true }

    // nil target → .all matches the documented default at the type's doc comment.
    switch context.phase.target ?? .all {
    case .randomOne:
      assignRandomOne(
        active: active, sourceData: sourceData, state: &state, emitter: context.emitter
      )
    case .all:
      assignAll(
        active: active, sourceData: sourceData, state: &state, emitter: context.emitter
      )
    }
  }

  /// Assigns minority value to one random agent, majority to the rest.
  ///
  /// Precondition: `sourceData` is `.arrayOfDictionaries`. `ScenarioValidator`
  /// rejects mismatched shapes upstream — the `guard` fall-through is a no-op
  /// safety net for scenarios constructed in tests or future code paths that
  /// bypass validation.
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
  ///
  /// Precondition: `sourceData` is `.array` or `.string`. `ScenarioValidator`
  /// rejects `.arrayOfDictionaries` / `.dictionary` upstream — the `default`
  /// branch's empty-string fallback is a no-op safety net for scenarios
  /// constructed in tests or future code paths that bypass validation.
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
