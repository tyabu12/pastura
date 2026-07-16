import Foundation
import Testing

@testable import Pastura

/// Behavioral tests for the ADR-018 format-preserving boundary sync wired into
/// `ScenarioEditorViewModel` (#725). A scalar-only visual edit on a loaded,
/// commented scenario must preserve the user's comments / key order through
/// `switchToYAMLMode()` and `save()`; structural edits fall back to canonical
/// serialization. Sibling extension — no new `@Suite` (see
/// `.claude/rules/testing.md` § "Splitting a Suite Across Files").
extension ScenarioEditorViewModelTests {

  /// A stored scenario with head/inline comments and a block-scalar context —
  /// the formatting a full re-serialize would destroy.
  static var commentedYAML: String {
    """
    # Scenario header comment
    id: boundary_sync_test
    language: en
    name: Original Title  # the display name
    description: A scenario for boundary-sync testing
    agents: 2
    rounds: 2
    context: |
      Some shared context.
    personas:
      - name: Alice  # first agent
        description: An agent
        secret: She sold the house  # the twist
      - name: Bob
        description: Another agent
    phases:
      - type: speak_all
        prompt: |
          Speak.
        output:
          statement: string
    """
  }

  private func loadedEditor() async throws -> (ScenarioEditorViewModel, GRDBScenarioRepository) {
    let (sut, repo) = try makeSUTWithRepo()
    try repo.save(
      ScenarioRecord(
        id: "boundary_sync_test", name: "Original Title",
        yamlDefinition: Self.commentedYAML, isPreset: false, createdAt: Date(), updatedAt: Date()))
    await sut.loadForEditing(scenarioId: "boundary_sync_test")
    return (sut, repo)
  }

  @Test func visualScalarEditPreservesCommentsOnModeSwitch() async throws {
    let (sut, _) = try await loadedEditor()
    #expect(sut.editorMode == .visual)

    sut.scenarioName = "Renamed Title"  // a scalar-only visual edit
    // An existing single-line secret is scalar-patchable too (#914) — edited
    // alongside the name so this case covers the field interaction, not just
    // each field in isolation.
    sut.personas[0].secret = "She burned the deed"
    sut.switchToYAMLMode()

    #expect(sut.yamlText.contains("# Scenario header comment"))
    #expect(sut.yamlText.contains("name: Renamed Title  # the display name"))
    #expect(sut.yamlText.contains("# first agent"))  // persona comment kept
    #expect(sut.yamlText.contains("# the twist"))  // secret's inline comment kept
    #expect(sut.yamlText.contains("She burned the deed"))
    #expect(!sut.yamlText.contains("Original Title"))
    #expect(!sut.yamlText.contains("She sold the house"))
  }

  /// The editor boundary's half of the empty ≡ absent rule (#914): clearing the
  /// field emits no `secret:` key rather than `secret: ""`.
  @Test func clearedSecretIsOmittedFromYAML() async throws {
    let (sut, _) = try await loadedEditor()
    #expect(sut.personas[0].secret == "She sold the house")

    sut.personas[0].secret = "   "  // whitespace-only → trimmed to empty → nil
    sut.switchToYAMLMode()

    #expect(!sut.yamlText.contains("secret:"))
    #expect(!sut.yamlText.contains("She sold the house"))
  }

  @Test func visualScalarEditSavePersistsPreservedComments() async throws {
    let (sut, repo) = try await loadedEditor()

    sut.scenarioName = "Renamed Title"
    let saved = await sut.save()

    #expect(saved)
    let record = try repo.fetchById("boundary_sync_test")
    #expect(record?.yamlDefinition.contains("# Scenario header comment") == true)
    #expect(record?.yamlDefinition.contains("name: Renamed Title  # the display name") == true)
  }

  @Test func structuralVisualEditFallsBackOnModeSwitch() async throws {
    let (sut, _) = try await loadedEditor()

    // Adding a persona is a structural change → full canonical serialize, so
    // the original formatting is (acceptably) not preserved.
    sut.personas.append(EditablePersona(name: "Carol", description: "A third agent"))
    sut.switchToYAMLMode()

    #expect(!sut.yamlText.contains("# Scenario header comment"))
    #expect(sut.yamlText.contains("Carol"))
  }
}
