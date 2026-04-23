import Foundation
import Testing

@testable import Pastura

// Tests that `SimulationViewModel.run()` brackets its inference activity
// with the shared `SimulationActivityRegistry`, so the Settings Models
// section can disable model switching while a simulation is in flight.
//
// Split as a sibling extension per testing.md: a new `@Suite` would race
// against the original suite on shared DatabaseManager + SimulationRunner
// state, silently on fast local machines and visibly on CI.
extension SimulationViewModelLifecycleTests {

  @Test func runLeavesActivityRegistryOnLoadFailure() async throws {
    let registry = SimulationActivityRegistry()

    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      simulationActivityRegistry: registry
    )
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1)

    #expect(!registry.isActive, "idle before run")

    await sut.run(scenario: scenario, llm: FailingLLMService())

    // If enter() were missing, `leave()` inside the defer would trap on
    // the `activeCount > 0` precondition — so reaching this assertion
    // implies enter() fired before the defer was registered.
    #expect(!registry.isActive, "defer must leave() on load-failure path")
    #expect(registry.activeCount == 0)
  }

  @Test func runLeavesActivityRegistryOnCompletion() async throws {
    let registry = SimulationActivityRegistry()

    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      simulationActivityRegistry: registry
    )
    sut.speed = .instant

    let mock = MockLLMService(responses: [
      #"{"statement": "hi from Alice"}"#,
      #"{"statement": "hi from Bob"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    #expect(sut.isCompleted, "sanity: simulation should complete with valid responses")
    #expect(!registry.isActive, "defer must leave() on completion path")
    #expect(registry.activeCount == 0)
  }
}
