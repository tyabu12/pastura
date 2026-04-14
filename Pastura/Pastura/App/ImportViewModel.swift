import Foundation

/// ViewModel for the YAML scenario import screen.
///
/// Handles YAML input validation, parsing feedback, and saving to the repository.
@Observable
final class ImportViewModel {
  var yamlText: String = ""
  private(set) var validationErrors: [String] = []
  private(set) var isValid = false
  private(set) var isSaving = false
  private(set) var savedScenarioId: String?

  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()
  private let validator = ScenarioValidator()

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  /// Validates the current YAML text and updates validation state.
  func validate() {
    validationErrors = []
    isValid = false

    let trimmed = yamlText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      validationErrors = ["YAML is empty"]
      return
    }

    do {
      let scenario = try loader.load(yaml: trimmed)
      _ = try validator.validate(scenario)
      isValid = true
    } catch {
      validationErrors = [error.localizedDescription]
    }
  }

  /// Saves the validated YAML as a new scenario.
  func save() async -> Bool {
    guard isValid else { return false }
    isSaving = true
    defer { isSaving = false }

    do {
      let scenario = try loader.load(yaml: yamlText)

      // Check for ID collision
      if let existing = try await offMain({ [repository] in
        try repository.fetchById(scenario.id)
      }) {
        if existing.isPreset {
          validationErrors = ["Cannot overwrite preset scenario '\(existing.name)'"]
          return false
        }
        if existing.sourceType == ScenarioSourceType.gallery {
          validationErrors = [
            "Cannot overwrite gallery scenario '\(existing.name)'. "
              + "Use Share Board to update, or delete the local copy first."
          ]
          return false
        }
      }

      let record = ScenarioRecord(
        id: scenario.id,
        name: scenario.name,
        yamlDefinition: yamlText,
        isPreset: false,
        createdAt: Date(),
        updatedAt: Date()
      )
      try await offMain { [repository] in
        try repository.save(record)
      }
      savedScenarioId = scenario.id
      return true
    } catch {
      validationErrors = ["Save failed: \(error.localizedDescription)"]
      return false
    }
  }

  /// Loads YAML text from an editing scenario. Gallery-sourced rows are
  /// read-only and not opened for editing here; the user gets an error
  /// prompt instead.
  func loadForEditing(scenarioId: String) async {
    do {
      if let record = try await offMain({ [repository] in
        try repository.fetchById(scenarioId)
      }) {
        if record.sourceType == ScenarioSourceType.gallery {
          validationErrors = [
            "Gallery scenarios are read-only. Use Share Board to update."
          ]
          return
        }
        yamlText = record.yamlDefinition
        validate()
      }
    } catch {
      validationErrors = ["Failed to load: \(error.localizedDescription)"]
    }
  }

  // MARK: - Scenario Generation Prompt

  /// A copyable prompt for generating YAML scenarios via external LLM.
  static let scenarioGenerationPrompt = """
    Generate a YAML scenario for Pastura (AI multi-agent simulation).
    Required structure:

    id: unique_snake_case_id
    name: Scenario Name
    description: Brief description
    agents: <number 2-10>
    rounds: <number 1-30>
    context: Shared context for all agents
    personas:
      - name: Agent Name
        description: Character description
    phases:
      - type: <speak_all|speak_each|vote|choose|score_calc|assign|eliminate|summarize>
        prompt: Prompt template (for LLM phases)
        output:
          field_name: string

    Available phase types: speak_all, speak_each, vote, choose, \
    score_calc (logic: prisoners_dilemma|vote_tally|wordwolf_judge), \
    assign (source: key, target: all), eliminate, summarize (template: text).
    """
}
