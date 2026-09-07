import Testing

@testable import Pastura

/// The `yamlDefinition:` argument for a `SimulationViewModel.run(...)` call on
/// a synthetic `Scenario` (`makeTestScenario` and friends).
///
/// Since ADR-023 S5-5 every fresh run goes through the Kotlin engine, whose
/// `ScenarioLoader` owns the parse — a Swift `Scenario` is not convertible, so
/// the App-layer suites hand in the editor round-trip (`ScenarioSerializer`)
/// of the scenario they built. The round-trip is re-loaded on the Swift loader
/// here and checked against the original's shape, so a scenario the serializer
/// cannot express — or expresses lossily, which would make the engine run
/// something other than what the call site's assertions describe — fails at
/// the call site as a recorded issue, rather than as a green test or a
/// `.scenarioValidationFailed` event deep in the run.
/// `LoaderAcceptanceParityTests` guards the Kotlin side.
///
/// Not `throws`: the call sites include `Task { await sut.run(...) }` bodies,
/// where a throwing helper would turn the task into a `Task<Void, Error>`.
func yamlDefinition(for scenario: Scenario) -> String {
  let yaml = ScenarioSerializer().serialize(scenario)
  do {
    let reloaded = try ScenarioLoader().load(yaml: yaml)
    let same =
      reloaded.rounds == scenario.rounds
      && reloaded.agentCount == scenario.agentCount
      && reloaded.personas.map(\.name) == scenario.personas.map(\.name)
      && reloaded.phases.map(\.type) == scenario.phases.map(\.type)
      && reloaded.extraData == scenario.extraData
    if !same {
      Issue.record("yamlDefinition(for:) round-trip is lossy for scenario '\(scenario.id)'")
    }
  } catch {
    Issue.record("yamlDefinition(for:) produced YAML the Swift loader rejects: \(error)")
  }
  return yaml
}
