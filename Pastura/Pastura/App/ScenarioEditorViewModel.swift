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

/// Mutable phase for visual editing.
///
/// Separates editing state from the immutable ``Phase`` domain model.
/// Exposes all phase fields; type-dependent visibility is handled by the UI.
///
/// Conditional-specific fields (`condition`, `thenPhases`, `elsePhases`)
/// hold nested `EditablePhase` values so the editor can recursively render
/// sub-phase blocks. Depth-1 is enforced at the editor layer by filtering
/// `.conditional` out of the type picker when `PhaseEditorSheet` is opened
/// for a nested phase.
struct EditablePhase: Identifiable, Sendable {
  let id = UUID()
  var type: PhaseType
  var prompt: String
  var outputFields: [String: String]
  var options: [String]
  var pairing: PairingStrategy?
  var logic: ScoreCalcLogic?
  var template: String
  var source: String
  var target: String
  var excludeSelf: Bool
  var subRounds: Int?
  var condition: String
  var thenPhases: [EditablePhase]
  var elsePhases: [EditablePhase]

  // swiftlint:disable:next function_default_parameter_at_end
  init(
    type: PhaseType = .speakAll,
    prompt: String = "",
    outputFields: [String: String] = [:],
    options: [String] = [],
    pairing: PairingStrategy? = nil,
    logic: ScoreCalcLogic? = nil,
    template: String = "",
    source: String = "",
    target: String = "",
    excludeSelf: Bool = false,
    subRounds: Int? = nil,
    condition: String = "",
    thenPhases: [EditablePhase] = [],
    elsePhases: [EditablePhase] = []
  ) {
    self.type = type
    self.prompt = prompt
    self.outputFields = outputFields
    self.options = options
    self.pairing = pairing
    self.logic = logic
    self.template = template
    self.source = source
    self.target = target
    self.excludeSelf = excludeSelf
    self.subRounds = subRounds
    self.condition = condition
    self.thenPhases = thenPhases
    self.elsePhases = elsePhases
  }

  init(from phase: Phase) {
    self.type = phase.type
    self.prompt = phase.prompt ?? ""
    self.outputFields = phase.outputSchema ?? [:]
    self.options = phase.options ?? []
    self.pairing = phase.pairing
    self.logic = phase.logic
    self.template = phase.template ?? ""
    self.source = phase.source ?? ""
    self.target = phase.target?.rawValue ?? ""
    self.excludeSelf = phase.excludeSelf ?? false
    self.subRounds = phase.subRounds
    self.condition = phase.condition ?? ""
    self.thenPhases = phase.thenPhases?.map { EditablePhase(from: $0) } ?? []
    self.elsePhases = phase.elsePhases?.map { EditablePhase(from: $0) } ?? []
  }

  func toPhase() -> Phase {
    let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
    return Phase(
      type: type,
      prompt: prompt.isEmpty ? nil : prompt,
      outputSchema: outputFields.isEmpty ? nil : outputFields,
      options: options.isEmpty ? nil : options,
      pairing: pairing,
      logic: logic,
      template: template.isEmpty ? nil : template,
      source: source.isEmpty ? nil : source,
      // Invalid strings silently nil here — the editor's `validate()` surfaces
      // a user-visible error before this point so typos don't reach the engine.
      target: trimmedTarget.isEmpty ? nil : AssignTarget(rawValue: trimmedTarget),
      excludeSelf: excludeSelf ? true : nil,
      subRounds: subRounds,
      condition: trimmedCondition.isEmpty ? nil : trimmedCondition,
      thenPhases: thenPhases.isEmpty ? nil : thenPhases.map { $0.toPhase() },
      elsePhases: elsePhases.isEmpty ? nil : elsePhases.map { $0.toPhase() }
    )
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
      validationErrors = ["Template load failed: \(error.localizedDescription)"]
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
            "Gallery scenarios are read-only. Use Share Board to update."
          ]
          return
        }
        let scenario = try loader.load(yaml: record.yamlDefinition)
        populateFromScenario(scenario)
        yamlText = record.yamlDefinition
        validationErrors = []
      }
    } catch {
      validationErrors = ["Failed to load: \(error.localizedDescription)"]
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
      validationErrors = ["YAML is empty"]
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
        validationErrors = ["YAML is empty"]
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
        validationErrors.append("Scenario name is required")
      }
      if scenarioId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        validationErrors.append("Scenario ID is required")
      }
      if personas.isEmpty {
        validationErrors.append("At least one persona is required")
      }
      if phases.isEmpty {
        validationErrors.append("At least one phase is required")
      }

      validationErrors.append(contentsOf: invalidAssignTargetErrors())

      if !validationErrors.isEmpty { return }

      scenario = buildScenario()
    }

    do {
      _ = try validator.validate(scenario)
      isValid = true
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
      validationErrors = ["Save failed: \(error.localizedDescription)"]
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
          "Phase \(idx + 1) (assign): unknown target '\(trimmed)'. Use 'all' or 'random_one'."
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
      phases: phases.map { $0.toPhase() }
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
  }
}
