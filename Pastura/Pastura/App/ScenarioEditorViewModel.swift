import Foundation

/// Editor mode for the dual-mode scenario editor.
enum EditorMode: Sendable {
  case visual
  case yaml
}

/// Mutable persona for visual editing.
///
/// Separates editing state from the immutable ``Persona`` domain model.
struct EditablePersona: Identifiable, Sendable {
  let id = UUID()
  var name: String
  var description: String

  init(name: String = "", description: String = "") {
    self.name = name
    self.description = description
  }

  init(from persona: Persona) {
    self.name = persona.name
    self.description = persona.description
  }

  func toPersona() -> Persona {
    Persona(name: name, description: description)
  }
}

/// ViewModel for the dual-mode scenario editor (visual form + raw YAML).
///
/// Manages editor state for both modes and handles mode switching,
/// validation, template loading, and save flow. YAML is the source of truth:
/// visual edits are serialized to YAML on mode switch and on save.
@Observable
final class ScenarioEditorViewModel {

  // MARK: - Visual Mode State

  var scenarioId: String = ""
  var scenarioName: String = ""
  var scenarioDescription: String = ""
  var agentCount: Int = 2
  var rounds: Int = 1
  var context: String = ""
  var personas: [EditablePersona] = []
  var phases: [EditablePhase] = []

  // MARK: - YAML Mode State

  var yamlText: String = ""

  // MARK: - Editor State

  var editorMode: EditorMode = .visual
  private(set) var validationErrors: [String] = []
  private(set) var isValid = false
  private(set) var isSaving = false
  private(set) var savedScenarioId: String?

  // MARK: - Dependencies

  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()
  private let serializer = ScenarioSerializer()
  private let validator = ScenarioValidator()
  private let contentValidator = ScenarioContentValidator()

  /// Stores top-level YAML keys that the visual editor has no UI for.
  ///
  /// Captured in `populateFromScenario` so `buildScenario` can pass them
  /// through unchanged — preventing a silent data loss on every visual-mode save
  /// for scenarios with custom fields (e.g. bokete `topics`, word_wolf `words`).
  private var carriedExtraData: [String: AnyCodableValue] = [:]

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  // MARK: - Template Loading

  /// Loads a scenario from YAML as a template for a new scenario.
  ///
  /// Generates a new UUID-based ID to prevent collision with the original.
  func loadFromTemplate(yaml: String) {
    do {
      let scenario = try loader.load(yaml: yaml)
      populateFromScenario(scenario)
      // Generate new ID to avoid overwriting the template
      scenarioId = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
      validationErrors = []
    } catch {
      validationErrors = [
        String(localized: "Template load failed: \(error.localizedDescription)")
      ]
    }
  }

  /// Loads an existing scenario for editing (preserves original ID).
  /// Gallery-sourced rows are read-only and refuse to load for editing.
  func loadForEditing(scenarioId: String) async {
    do {
      if let record = try await offMain({ [repository] in
        try repository.fetchById(scenarioId)
      }) {
        if record.sourceType == ScenarioSourceType.gallery {
          validationErrors = [
            String(localized: "Gallery scenarios are read-only. Use Share Board to update.")
          ]
          return
        }
        let scenario = try loader.load(yaml: record.yamlDefinition)
        populateFromScenario(scenario)
        yamlText = record.yamlDefinition
        validationErrors = []
      }
    } catch {
      validationErrors = [
        String(localized: "Failed to load: \(error.localizedDescription)")
      ]
    }
  }

  // MARK: - Mode Switching

  /// Switches from visual mode to YAML mode.
  ///
  /// Serializes the current visual state to YAML text.
  func switchToYAMLMode() {
    let scenario = buildScenario()
    yamlText = serializer.serialize(scenario)
    editorMode = .yaml
  }

  /// Attempts to switch from YAML mode to visual mode.
  ///
  /// Parses the current YAML text. If parsing fails, stays in YAML mode
  /// and shows validation errors.
  /// - Returns: `true` if switch succeeded, `false` if YAML is invalid.
  @discardableResult
  func switchToVisualMode() -> Bool {
    let trimmed = yamlText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      validationErrors = [String(localized: "YAML is empty")]
      return false
    }

    do {
      let scenario = try loader.load(yaml: trimmed)
      populateFromScenario(scenario)
      validationErrors = []
      editorMode = .visual
      return true
    } catch {
      validationErrors = [error.localizedDescription]
      return false
    }
  }

  // MARK: - Validation

  /// Validates the current editor state (from whichever mode is active).
  func validate() {
    validationErrors = []
    isValid = false

    let scenario: Scenario
    if editorMode == .yaml {
      let trimmed = yamlText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        validationErrors = [String(localized: "YAML is empty")]
        return
      }
      do {
        scenario = try loader.load(yaml: trimmed)
      } catch {
        validationErrors = [error.localizedDescription]
        return
      }
    } else {
      // Visual mode: check basic fields first
      if scenarioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        validationErrors.append(String(localized: "Scenario name is required"))
      }
      if scenarioId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        validationErrors.append(String(localized: "Scenario ID is required"))
      }
      if personas.isEmpty {
        validationErrors.append(String(localized: "At least one persona is required"))
      }
      if phases.isEmpty {
        validationErrors.append(String(localized: "At least one phase is required"))
      }

      validationErrors.append(contentsOf: invalidAssignTargetErrors())

      if !validationErrors.isEmpty { return }

      scenario = buildScenario()
    }

    do {
      _ = try validator.validate(scenario)
      let contentFindings = contentValidator.validate(scenario)
      validationErrors.append(contentsOf: contentFindings)
      if validationErrors.isEmpty {
        isValid = true
      }
    } catch {
      validationErrors = [error.localizedDescription]
    }
  }

  // MARK: - Save

  /// Saves the current scenario to the repository.
  ///
  /// Serializes visual state to YAML if in visual mode. Checks for
  /// preset collision before saving.
  /// - Returns: `true` if save succeeded.
  func save() async -> Bool {
    validate()
    guard isValid else { return false }
    isSaving = true
    defer { isSaving = false }

    let scenario = buildScenario()
    let yaml = serializer.serialize(scenario)

    do {
      // Check for preset collision
      if let existing = try await offMain({ [repository] in
        try repository.fetchById(scenario.id)
      }) {
        if existing.isPreset {
          validationErrors = [
            String(localized: "Cannot overwrite preset scenario '\(existing.name)'")
          ]
          return false
        }
        if existing.sourceType == ScenarioSourceType.gallery {
          validationErrors = [
            String(
              localized:
                "Cannot overwrite gallery scenario '\(existing.name)'. Use Share Board to update, or delete the local copy first."
            )
          ]
          return false
        }
      }

      let record = ScenarioRecord(
        id: scenario.id,
        name: scenario.name,
        yamlDefinition: yaml,
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
      validationErrors = [
        String(localized: "Save failed: \(error.localizedDescription)")
      ]
      return false
    }
  }

  // MARK: - Private

  /// Visual editor uses a free-text TextField for `target` (#83 will replace
  /// with a Picker). Surface typos as user-visible errors so they do not silently
  /// nil through `EditablePhase.toPhase()` and reach the engine as `.all`.
  private func invalidAssignTargetErrors() -> [String] {
    var errors: [String] = []
    for (idx, phase) in phases.enumerated() where phase.type == .assign {
      let trimmed = phase.target.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, AssignTarget(rawValue: trimmed) == nil {
        errors.append(
          String(
            localized:
              "Phase \(idx + 1) (assign): unknown target '\(trimmed)'. Use 'all' or 'random_one'."
          )
        )
      }
    }
    return errors
  }

  /// Builds a ``Scenario`` from the current visual editor state.
  private func buildScenario() -> Scenario {
    Scenario(
      id: scenarioId,
      name: scenarioName,
      description: scenarioDescription,
      agentCount: personas.count,
      rounds: rounds,
      context: context,
      personas: personas.map { $0.toPersona() },
      phases: phases.map { $0.toPhase() },
      extraData: carriedExtraData
    )
  }

  /// Populates the visual editor fields from a parsed ``Scenario``.
  private func populateFromScenario(_ scenario: Scenario) {
    scenarioId = scenario.id
    scenarioName = scenario.name
    scenarioDescription = scenario.description
    agentCount = scenario.agentCount
    rounds = scenario.rounds
    context = scenario.context
    personas = scenario.personas.map { EditablePersona(from: $0) }
    phases = scenario.phases.map { EditablePhase(from: $0) }
    carriedExtraData = scenario.extraData
  }
}
