import Foundation
import Testing

@testable import Pastura

@MainActor
struct ScenarioDetailViewModelTests {
  private static let validYAML = """
    id: test_scenario
    name: Test
    description: A test scenario
    agents: 2
    rounds: 1
    context: Test context
    personas:
      - name: Alice
        description: Agent A
      - name: Bob
        description: Agent B
    phases:
      - type: speak_all
        prompt: "Say something"
        output:
          statement: string
    """

  @Test func loadParsesYAMLAndValidates() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    try repo.save(
      ScenarioRecord(
        id: "test_scenario", name: "Test", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "test_scenario")

    #expect(viewModel.scenario != nil)
    #expect(viewModel.scenario?.name == "Test")
    #expect(viewModel.scenario?.agentCount == 2)
    #expect(viewModel.estimatedInferences == 2)  // 2 agents * 1 round * 1 speak_all
    #expect(viewModel.validationError == nil)
    #expect(viewModel.canRun == true)
    #expect(viewModel.errorMessage == nil)
  }

  @Test func loadHandlesMissingScenario() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "nonexistent")

    #expect(viewModel.scenario == nil)
    #expect(viewModel.errorMessage == "Scenario not found")
  }

  @Test func loadDetectsValidationErrors() async throws {
    // Too many agents (>10) will trigger validation error
    let badYAML = """
      id: bad
      name: Bad
      description: Too many agents
      agents: 11
      rounds: 1
      context: Context
      personas:
        - name: A1
          description: d
        - name: A2
          description: d
        - name: A3
          description: d
        - name: A4
          description: d
        - name: A5
          description: d
        - name: A6
          description: d
        - name: A7
          description: d
        - name: A8
          description: d
        - name: A9
          description: d
        - name: A10
          description: d
        - name: A11
          description: d
      phases:
        - type: speak_all
          prompt: "hi"
          output:
            statement: string
      """

    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "bad", name: "Bad", yamlDefinition: badYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "bad")

    #expect(viewModel.scenario != nil)
    #expect(viewModel.validationError != nil)
    #expect(viewModel.canRun == false)
  }

  @Test func deleteScenarioReturnsTrue() async throws {
    let db = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try repo.save(
      ScenarioRecord(
        id: "del", name: "Del", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    let viewModel = ScenarioDetailViewModel(repository: repo)
    await viewModel.load(scenarioId: "del")
    let deleted = await viewModel.deleteScenario()

    #expect(deleted == true)
    #expect(try repo.fetchById("del") == nil)
  }
}
