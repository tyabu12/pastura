import Foundation
import Testing

@testable import Pastura

/// Readonly enforcement matrix for gallery-sourced scenarios. Each test
/// seeds a gallery row, then drives `ScenarioEditorViewModel` through both
/// editor modes (visual + YAML) plus the load-for-editing path, asserting
/// the gate fires with a user-visible error.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ReadonlyEnforcementTests {

  private static let validYAML = """
    id: gallery_test
    language: ja
    name: Gallery Test
    description: A gallery scenario
    agents: 2
    rounds: 1
    context: Context
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

  private func seedGalleryRecord(in repo: GRDBScenarioRepository) throws {
    try repo.save(
      ScenarioRecord(
        id: "gallery_test", name: "Gallery Test", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date(),
        sourceType: ScenarioSourceType.gallery,
        sourceId: "gallery_test", sourceHash: "h1"))
  }

  // MARK: - ScenarioEditorViewModel — Visual mode save

  @Test func editorVMSaveRefusesGalleryRow() async throws {
    let manager = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    try seedGalleryRecord(in: repo)

    let viewModel = ScenarioEditorViewModel(repository: repo)
    viewModel.yamlText = Self.validYAML
    // Editor defaults to .visual mode; populate visual state from YAML
    // so save()'s buildScenario() produces the matching id.
    let switched = viewModel.switchToVisualMode()
    #expect(switched)

    let didSave = await viewModel.save()
    #expect(didSave == false)
    #expect(
      viewModel.validationErrors.contains { $0.contains("gallery scenario") })
  }

  @Test func editorVMLoadForEditingRefusesGalleryRow() async throws {
    let manager = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    try seedGalleryRecord(in: repo)

    let viewModel = ScenarioEditorViewModel(repository: repo)
    await viewModel.loadForEditing(scenarioId: "gallery_test")

    #expect(
      viewModel.validationErrors.contains { $0.contains("read-only") })
  }

  // MARK: - ScenarioEditorViewModel — YAML mode save

  /// YAML-mode equivalent of `editorVMSaveRefusesGalleryRow` (visual
  /// path above). The editor must enforce gallery-overwrite refusal
  /// regardless of which mode the user typed in, since `save()` routes
  /// through `currentScenario()` and reads the same
  /// `checkNoOverwriteCollision`.
  @Test func editorVMYAMLModeSaveRefusesGalleryRow() async throws {
    let manager = try DatabaseManager.inMemory()
    let repo = GRDBScenarioRepository(dbWriter: manager.dbWriter)
    try seedGalleryRecord(in: repo)

    let viewModel = ScenarioEditorViewModel(repository: repo)
    viewModel.yamlText = Self.validYAML  // same id as seeded gallery row
    viewModel.editorMode = .yaml

    let didSave = await viewModel.save()
    #expect(didSave == false)
    #expect(
      viewModel.validationErrors.contains { $0.contains("gallery scenario") })
  }
}
