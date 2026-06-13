import Foundation
import Testing

@testable import Pastura

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct SimulationViewModelExportTests {

  private let env = ResultMarkdownExporter.ExportEnvironment(
    deviceModel: "iPhone", osVersion: "Version 17.5")

  @Test func fetchExportPayloadReturnsNilWhenSimulationHasNotStarted() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      scenarioRepository: scenarioRepo)

    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    #expect(payload == nil)
  }

  @Test func fetchExportPayloadReturnsPayloadAfterSuccessfulRun() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test Scenario",
        yamlDefinition: "name: Test Scenario\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      scenarioRepository: scenarioRepo)
    sut.speed = .instant

    let mock = MockLLMService(responses: [
      #"{"statement": "hello from Alice"}"#,
      #"{"statement": "hello from Bob"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    await sut.run(scenario: scenario, llm: mock)

    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    let unwrapped = try #require(payload)
    #expect(unwrapped.text.contains("<!-- pastura-export v1 -->"))
    #expect(unwrapped.text.contains("# Simulation Export: Test Scenario"))
    #expect(unwrapped.text.contains("**Status**: Completed"))
    #expect(unwrapped.text.contains("hello from Alice"))
    #expect(unwrapped.fileURL.pathExtension == "md")
  }

  @Test func fetchExportPayloadReturnsNilForFailedRun() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test",
        yamlDefinition: "", isPreset: false,
        createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      scenarioRepository: scenarioRepo)
    sut.speed = .instant

    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 1)
    await sut.run(scenario: scenario, llm: FailingLLMService())

    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    #expect(payload == nil)
  }

  @Test func fetchExportPayloadReturnsNilWhenScenarioRepoNotInjected() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test",
        yamlDefinition: "", isPreset: false,
        createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo)  // no scenarioRepository
    sut.speed = .instant

    let mock = MockLLMService(responses: [#"{"statement": "hi"}"#, #"{"statement": "hi"}"#])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])])
    await sut.run(scenario: scenario, llm: mock)

    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    #expect(payload == nil)
  }

  @Test func runPopulatesScenarioSnapshotThatSurvivesScenarioDelete() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    // The scenario must exist at run time (FK enforced); it is deleted after.
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test Scenario",
        yamlDefinition: "name: Test Scenario\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo,
      turnRepository: turnRepo,
      scenarioRepository: scenarioRepo)
    sut.speed = .instant

    let mock = MockLLMService(responses: [
      #"{"statement": "hi"}"#, #"{"statement": "yo"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])])

    await sut.run(scenario: scenario, llm: mock)

    let simId = try #require(sut.simulationId)
    let afterRun = try #require(try simRepo.fetchById(simId))
    let snapshotYAML = try #require(afterRun.scenarioYamlSnapshot)
    #expect(afterRun.scenarioNameSnapshot == "Test Scenario")
    // The snapshot is re-serialized from the live domain object, so it
    // round-trips through ScenarioLoader to the same roster — independent of
    // whether the scenario row was ever persisted.
    let reparsed = try ScenarioLoader().load(yaml: snapshotYAML)
    #expect(reparsed.personas.map(\.name) == ["Alice", "Bob"])

    // Deleting the scenario orphans the run (SET NULL) but keeps the snapshot.
    try scenarioRepo.delete("test")
    let afterDelete = try #require(try simRepo.fetchById(simId))
    #expect(afterDelete.scenarioId == nil)
    #expect(afterDelete.scenarioNameSnapshot == "Test Scenario")
    #expect(afterDelete.scenarioYamlSnapshot == snapshotYAML)
  }

  @Test func fetchExportPayloadSucceedsForOrphanedRunAfterScenarioDelete() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test Scenario", yamlDefinition: "name: Test Scenario\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo,
      scenarioRepository: scenarioRepo)
    sut.speed = .instant
    let mock = MockLLMService(responses: [#"{"statement": "hi"}"#, #"{"statement": "yo"}"#])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])])
    await sut.run(scenario: scenario, llm: mock)

    // Delete the source scenario — the run is now orphaned (scenarioId nil).
    try scenarioRepo.delete("test")

    // Export still succeeds, reconstructing the scenario from the snapshot.
    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    let unwrapped = try #require(payload)
    #expect(unwrapped.text.contains("# Simulation Export: Test Scenario"))
    #expect(unwrapped.text.contains("hi"))
  }

  @Test func fetchExportPayloadUsesSnapshotNotEditedLiveScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test Scenario", yamlDefinition: "name: Test Scenario\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let sut = SimulationViewModel(
      simulationRepository: simRepo, turnRepository: turnRepo,
      scenarioRepository: scenarioRepo)
    sut.speed = .instant
    let mock = MockLLMService(responses: [#"{"statement": "hi"}"#, #"{"statement": "yo"}"#])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])])
    await sut.run(scenario: scenario, llm: mock)

    // Edit the live scenario after the run completes (upsert same id, new name).
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "EDITED NAME", yamlDefinition: "name: EDITED NAME\n",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    // Export reflects the snapshot (what ran), not the edited live scenario.
    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    let unwrapped = try #require(payload)
    #expect(unwrapped.text.contains("# Simulation Export: Test Scenario"))
    #expect(!unwrapped.text.contains("EDITED NAME"))
  }
}
