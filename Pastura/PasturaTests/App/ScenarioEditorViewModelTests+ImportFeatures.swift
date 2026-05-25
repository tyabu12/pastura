import Foundation
import Testing

@testable import Pastura

/// Tests for the YAML-import features folded into ScenarioEditorViewModel
/// after `ImportView` consolidation: file-URL loading, generation-prompt
/// constant, and the `isNewScenario` flag that gates the new-scenario-only
/// affordances in the editor toolbar.
extension ScenarioEditorViewModelTests {

  // MARK: - loadFromFile

  @Test func loadFromFileSuccessSetsYAMLAndSwitchesToYAMLMode() async throws {
    let sut = try makeSUT()
    let tempURL = try writeTempFile(
      contents: Data(Self.validYAML.utf8), suffix: ".yaml")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    await sut.loadFromFile(url: tempURL)

    #expect(sut.yamlText == Self.validYAML)
    #expect(sut.editorMode == .yaml)
    #expect(sut.validationErrors.isEmpty)
  }

  @Test func loadFromFileNonExistentURLSurfacesError() async throws {
    let sut = try makeSUT()
    let nonExistentURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("does-not-exist-\(UUID().uuidString).yaml")

    await sut.loadFromFile(url: nonExistentURL)

    #expect(sut.yamlText.isEmpty)
    #expect(!sut.validationErrors.isEmpty)
  }

  @Test func loadFromFileNonUTF8SurfacesError() async throws {
    let sut = try makeSUT()
    // 0xFF / 0xFE are invalid UTF-8 lead bytes.
    let invalidUTF8 = Data([0xFF, 0xFE, 0xFD, 0xFC])
    let tempURL = try writeTempFile(contents: invalidUTF8, suffix: ".yaml")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    await sut.loadFromFile(url: tempURL)

    #expect(sut.yamlText.isEmpty)
    #expect(!sut.validationErrors.isEmpty)
  }

  // MARK: - isNewScenario

  @Test func isNewScenarioIsTrueForFreshEditor() throws {
    let sut = try makeSUT()
    #expect(sut.isNewScenario)
  }

  @Test func isNewScenarioRemainsTrueAfterLoadFromTemplate() throws {
    let sut = try makeSUT()
    sut.loadFromTemplate(yaml: Self.validYAML)
    // Template path generates a fresh UUID — the user is still authoring a
    // new scenario, just seeded from gallery content.
    #expect(sut.isNewScenario)
  }

  @Test func isNewScenarioIsFalseAfterLoadForEditing() async throws {
    let (sut, repo) = try makeSUTWithRepo()
    try repo.save(
      ScenarioRecord(
        id: "user_owned_test", name: "Owned", yamlDefinition: Self.validYAML,
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))

    await sut.loadForEditing(scenarioId: "user_owned_test")

    #expect(!sut.isNewScenario)
  }

  // MARK: - scenarioGenerationPrompt

  @Test func scenarioGenerationPromptIsNotEmpty() {
    #expect(!ScenarioGenerationPrompt.text.isEmpty)
  }

  // MARK: - Temp-file helper

  private func writeTempFile(contents: Data, suffix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("scenario-editor-test-\(UUID().uuidString)\(suffix)")
    try contents.write(to: url)
    return url
  }
}
