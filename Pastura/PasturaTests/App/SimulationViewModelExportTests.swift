import Foundation
import Testing

@testable import Pastura

@Suite(.serialized) @MainActor
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
    sut.speed = .fastest

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
    #expect(unwrapped.text.contains("**Status**: completed"))
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
    sut.speed = .fastest

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
    sut.speed = .fastest

    let mock = MockLLMService(responses: [#"{"statement": "hi"}"#, #"{"statement": "hi"}"#])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"], rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])])
    await sut.run(scenario: scenario, llm: mock)

    let payload = try await sut.fetchExportPayload(exportEnvironment: env)
    #expect(payload == nil)
  }
}
