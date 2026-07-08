// swiftlint:disable file_length
//
// ScenarioEditorViewModel cohesively manages the dual-mode (visual + YAML)
// editor's parallel state buffers and the `currentScenario()` funnel that
// reconciles them. Splitting state mutators across sibling files would force
// loosening `private(set)` boundaries that intentionally encapsulate write
// access — a worse trade than the size budget. Precedent: SimulationViewModel,
// ModelDownloader, YAMLReplayExporter use the same cohesion-vs-length disable.

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
/// State is intentionally a **dual buffer**: visual fields and `yamlText`
/// are independent, each the source of truth for whichever mode the user
/// last touched. `currentScenario()` is the single mode-dispatch funnel
/// that materializes a `(Scenario, yaml)` pair — see PR #336 for the drift
/// class it resolves. New save / export / preview / share callsites MUST
/// route through `currentScenario()`; see `.claude/rules/scenario-editor.md`.
@Observable
final class ScenarioEditorViewModel {  // swiftlint:disable:this type_body_length

  // MARK: - Visual Mode State

  var scenarioId: String = ""
  var scenarioName: String = ""
  var scenarioDescription: String = ""
  /// Scenario authoring language. Seeded from the device locale via
  /// `LocaleResolver.deviceDefault()` for a fresh editor; overwritten in
  /// `populateFromScenario` when a template or existing scenario loads.
  /// ADR-010 D2 / D6 (new-scenario creation seed).
  var editorLanguage: String = LocaleResolver.deviceDefault()
  /// Optional cross-language override. Parsed-and-preserved in Step C-1,
  /// Engine-wired in Step E (ADR-010 D5). The Visual mode has no UI for
  /// this field yet — round-trip preservation only.
  var editorSimulationLanguage: String?
  var agentCount: Int = 2
  var rounds: Int = 1
  /// Optional prompt-side conversation-log window (#907). No Visual UI yet —
  /// carry-through only, so a value set in YAML mode (`log_window:`) survives a
  /// visual-mode save instead of being silently dropped. Mirrors
  /// `editorSimulationLanguage`.
  var editorLogWindow: Int?
  var context: String = ""
  var personas: [EditablePersona] = []
  var phases: [EditablePhase] = []

  // MARK: - YAML Mode State

  var yamlText: String = ""

  // MARK: - Editor State

  var editorMode: EditorMode = .visual
  private(set) var validationErrors: [String] = []
  /// Non-blocking semantic-lint findings (`.warning` / `.info`) from the most
  /// recent ``validate()``, surfaced in the editor's suggestions banner
  /// (ADR-024 PR2). `.error`-severity findings live in ``validationErrors``
  /// (blocking); these never block Save. Empty except immediately after a
  /// `validate()` that reached the linter — reset alongside `validationErrors`
  /// on every mode switch / load so a stale suggestion never outlives its scenario.
  private(set) var lintWarnings: [LintFinding] = []
  private(set) var isValid = false
  private(set) var isSaving = false
  private(set) var savedScenarioId: String?

  /// Set by ``loadForEditing(scenarioId:)`` to mark the editor as bound to
  /// an existing user-owned scenario. Stays `nil` for fresh editors and for
  /// template-seeded "Try this" flows (which generate a new id). Drives
  /// ``isNewScenario`` so the YAML-mode toolbar can hide new-creation-only
  /// affordances (file picker, copy-generation-prompt) while editing.
  private(set) var editingScenarioId: String?

  /// `true` when the editor is composing a new scenario (fresh open OR
  /// template-seeded) rather than editing an existing user-owned scenario.
  var isNewScenario: Bool { editingScenarioId == nil }

  // MARK: - Dependencies

  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()
  /// Format-preserving visual→YAML boundary sync (ADR-018). Splices changed
  /// scalar values into the existing `yamlText` (preserving comments / key
  /// order) and falls back to canonical full serialization otherwise.
  private let patcher = ScenarioYAMLPatcher()
  private let validator = ScenarioValidator()
  private let contentValidator = ScenarioContentValidator()
  /// Semantic linter (ADR-024). Its `.error` findings join the blocking
  /// `validationErrors` array; `.warning`/`.info` go to the non-blocking
  /// ``lintWarnings`` suggestions banner. Run on the same `Scenario` the
  /// validator sees (the `currentScenario()` funnel output) — never a fresh
  /// visual-state build, per the funnel invariant.
  private let linter = ScenarioSemanticLinter()

  /// Top-level YAML keys without a Visual UI, captured by
  /// `populateFromScenario` so `buildScenario` passes them through on
  /// visual-mode save (bokete `topics`, word_wolf `words`, …).
  ///
  /// Load-bearing for engine correctness — `scenario.extraData` is read at
  /// runtime by `AssignHandler.execute`, `EventInjectHandler.execute`, and
  /// `ScenarioValidator.{validateAssignPhaseShape,validateEventInjectShape}`.
  /// Removing the carry would silently drop these fields on visual-mode save.
  private var carriedExtraData: [String: AnyCodableValue] = [:]

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  // MARK: - Template Loading

  /// Loads a scenario from YAML as a template for a new scenario.
  ///
  /// Generates a new UUID-based ID to prevent collision with the original.
  func loadFromTemplate(yaml: String) {
    lintWarnings = []
    do {
      let scenario = try loader.load(yaml: yaml)
      populateFromScenario(scenario)
      // Generate new ID to avoid overwriting the template
      scenarioId = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
      validationErrors = []
    } catch {
      validationErrors = [
        String(format: String(localized: "Template load failed: %@"), error.localizedDescription)
      ]
    }
  }

  /// Loads an existing scenario for editing (preserves original ID).
  /// Gallery-sourced rows are read-only and refuse to load for editing.
  func loadForEditing(scenarioId: String) async {
    lintWarnings = []
    do {
      if let record = try await offMain({ [repository] in
        try repository.fetchById(scenarioId)
      }) {
        if record.sourceType == ScenarioSourceType.gallery {
          validationErrors = [
            String(localized: "Gallery scenarios are read-only. Use Shared Scenarios to update.")
          ]
          return
        }
        let scenario = try loader.load(yaml: record.yamlDefinition)
        populateFromScenario(scenario)
        yamlText = record.yamlDefinition
        editingScenarioId = scenarioId
        validationErrors = []
      }
    } catch {
      validationErrors = [
        String(format: String(localized: "Failed to load: %@"), error.localizedDescription)
      ]
    }
  }

  // MARK: - File Import (new-scenario flow)

  /// Loads YAML from a file URL into ``yamlText`` and switches to YAML mode.
  /// Surfaces I/O failures (security-scope denial, non-UTF8 content, iCloud
  /// lazy-fetch errors) into ``validationErrors`` rather than silently
  /// dropping them.
  ///
  /// The read happens off-MainActor so an iCloud-Drive lazy fetch does not
  /// block the UI. After a successful read, mode switches to `.yaml` and
  /// ``validate()`` runs so the user sees parse / structural errors right
  /// away.
  func loadFromFile(url: URL) async {
    lintWarnings = []
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    do {
      let content = try await offMain {
        try String(contentsOf: url, encoding: .utf8)
      }
      yamlText = content
      editorMode = .yaml
      validate()
    } catch {
      validationErrors = [
        String(format: String(localized: "Failed to read file: %@"), error.localizedDescription)
      ]
    }
  }

  /// Surfaces a system file-picker `.failure` (rare — e.g. iCloud auth or
  /// document-provider error before the picker yields a URL) to the
  /// validation banner. Routed through the same key as `loadFromFile`
  /// since both are file-I/O failures from the user's perspective.
  func surfaceFileImportError(_ error: any Error) {
    lintWarnings = []
    validationErrors = [
      String(format: String(localized: "Failed to read file: %@"), error.localizedDescription)
    ]
  }

  // MARK: - Mode Switching

  /// Switches from visual mode to YAML mode.
  ///
  /// Materializes the visual state to YAML via the format-preserving
  /// ``ScenarioYAMLPatcher`` (ADR-018): when only scalar values changed, the
  /// existing `yamlText` is patched in place so the user's comments / key order
  /// survive; structural or block-scalar changes (and a blank base) fall back to
  /// canonical serialization.
  func switchToYAMLMode() {
    lintWarnings = []
    let scenario = buildScenario()
    yamlText = patcher.patch(visual: scenario, base: yamlText)
    editorMode = .yaml
  }

  /// Attempts to switch from YAML mode to visual mode.
  ///
  /// Parses the current YAML text. If parsing fails, stays in YAML mode
  /// and shows validation errors.
  /// - Returns: `true` if switch succeeded, `false` if YAML is invalid.
  @discardableResult
  func switchToVisualMode() -> Bool {
    lintWarnings = []
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
    // Reset here (not only at the success point) so an early return below —
    // visual field error, empty YAML, parse/validator throw — clears a prior
    // run's suggestions instead of leaving them under a new blocking error.
    lintWarnings = []
    isValid = false

    // Mode-specific pre-checks (visual: field UX errors, YAML: empty guard).
    // Materialization itself is delegated to currentScenario() below so that
    // save() and validate() share one mode-dispatch funnel — see #336 for the
    // drift bug that motivated centralizing this.
    if editorMode == .visual {
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
    } else {
      let trimmed = yamlText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        validationErrors = [String(localized: "YAML is empty")]
        return
      }
    }

    let scenario: Scenario
    do {
      scenario = try currentScenario().scenario
    } catch {
      validationErrors = [error.localizedDescription]
      return
    }

    do {
      _ = try validator.validate(scenario)
      let contentFindings = contentValidator.validate(scenario)
      validationErrors.append(contentsOf: contentFindings)
      // Semantic-lint errors block commit alongside structural/content errors
      // (ADR-024). Same `scenario` value the validator received, per the
      // `currentScenario()` funnel. Warnings/info are non-blocking — routed to
      // `lintWarnings` for the suggestions banner (ADR-024 PR2).
      let findings = linter.lint(scenario)
      validationErrors.append(
        contentsOf: findings.filter { $0.severity == .error }.map(\.message))
      lintWarnings = findings.filter { $0.severity != .error }
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
  /// Materializes the scenario via `currentScenario()` so save honors whichever
  /// mode the user last touched. YAML mode persists the user's exact text
  /// (comments, key order); visual mode re-serializes the canonical form.
  /// Checks for preset collision before saving.
  /// - Returns: `true` if save succeeded.
  func save() async -> Bool {
    validate()
    guard isValid else { return false }
    isSaving = true
    defer { isSaving = false }

    let scenario: Scenario
    let yaml: String
    do {
      (scenario, yaml) = try currentScenario()
    } catch {
      // Defensive: validate() already proved currentScenario() succeeds for
      // the current state under @MainActor (no concurrent yamlText mutation).
      // Keep the catch as belt-and-braces so a future loader change cannot
      // crash the editor.
      validationErrors = [error.localizedDescription]
      return false
    }

    guard runCommitTimeValidation(scenario) else { return false }

    do {
      guard try await checkNoOverwriteCollision(scenarioId: scenario.id) else { return false }
      let record = ScenarioRecord(
        id: scenario.id,
        name: scenario.name,
        yamlDefinition: yaml,
        isPreset: false,
        createdAt: Date(),
        updatedAt: Date(),
        language: scenario.language
      )
      try await offMain { [repository] in
        try repository.save(record)
      }
      savedScenarioId = scenario.id
      return true
    } catch {
      validationErrors = [
        String(format: String(localized: "Save failed: %@"), error.localizedDescription)
      ]
      return false
    }
  }

  /// Rejects overwrites of preset and gallery-sourced scenarios with mode-specific
  /// error messages. Returns `true` when the id is free or refers to a user-owned
  /// scenario the editor may overwrite.
  private func checkNoOverwriteCollision(scenarioId: String) async throws -> Bool {
    let existing = try await offMain { [repository] in
      try repository.fetchById(scenarioId)
    }
    guard let existing else { return true }
    if existing.isPreset {
      validationErrors = [
        String(
          format: String(localized: "Cannot overwrite preset scenario '%@'"), existing.name)
      ]
      return false
    }
    if existing.sourceType == ScenarioSourceType.gallery {
      validationErrors = [
        String(
          format: String(
            localized:
              "Cannot overwrite gallery scenario '%@'. Use Shared Scenarios to update, or delete the local copy first."
          ), existing.name)
      ]
      return false
    }
    return true
  }

  // MARK: - Private

  /// Strict commit-time check: every LLM phase must declare its canonical
  /// primary field. Lives outside `validate()` so the visual editor's
  /// keystroke-time `validate()` stays lenient — users see canonical-field
  /// errors only at the Save action.
  private func runCommitTimeValidation(_ scenario: Scenario) -> Bool {
    do {
      _ = try validator.validateForCommit(scenario)
      return true
    } catch {
      validationErrors = [error.localizedDescription]
      return false
    }
  }

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
            format: String(
              localized:
                "Phase %lld (assign): unknown target '%@'. Use 'all' or 'random_one'."
            ), idx + 1, trimmed)
        )
      }
    }
    return errors
  }

  /// Returns the scenario plus its persistable YAML for the active editor mode.
  ///
  /// Single materialization point shared by `save()` and `validate()` so the
  /// mode dispatch lives in one place. Adding new callsites (preview, export,
  /// share) routes them through the same funnel and prevents silently reading
  /// from the wrong side — the drift class that produced #336.
  ///
  /// - YAML mode: parses `yamlText` and persists the user's *exact* text so
  ///   author-supplied comments and key order survive. Re-serializing would
  ///   normalize them away.
  /// - Visual mode: builds from typed fields and emits YAML via the
  ///   format-preserving ``ScenarioYAMLPatcher`` (ADR-018) against the current
  ///   `yamlText`, so a scalar-only visual edit on an existing scenario keeps
  ///   its comments / key order; structural / block-scalar / blank-base cases
  ///   fall back to canonical serialization.
  private func currentScenario() throws -> (scenario: Scenario, yaml: String) {
    switch editorMode {
    case .yaml:
      let trimmed = yamlText.trimmingCharacters(in: .whitespacesAndNewlines)
      let parsed = try loader.load(yaml: trimmed)
      return (parsed, trimmed)
    case .visual:
      let scenario = buildScenario()
      return (scenario, patcher.patch(visual: scenario, base: yamlText))
    }
  }

  /// Builds a ``Scenario`` from the current visual editor state.
  private func buildScenario() -> Scenario {
    Scenario(
      id: scenarioId,
      name: scenarioName,
      description: scenarioDescription,
      language: editorLanguage,
      simulationLanguage: editorSimulationLanguage,
      agentCount: personas.count,
      rounds: rounds,
      context: context,
      personas: personas.map { $0.toPersona() },
      phases: phases.map { $0.toPhase() },
      logWindow: editorLogWindow,
      extraData: carriedExtraData
    )
  }

  /// Populates the visual editor fields from a parsed ``Scenario``.
  private func populateFromScenario(_ scenario: Scenario) {
    scenarioId = scenario.id
    scenarioName = scenario.name
    scenarioDescription = scenario.description
    editorLanguage = scenario.language
    editorSimulationLanguage = scenario.simulationLanguage
    agentCount = scenario.agentCount
    rounds = scenario.rounds
    editorLogWindow = scenario.logWindow
    context = scenario.context
    personas = scenario.personas.map { EditablePersona(from: $0) }
    phases = scenario.phases.map { EditablePhase(from: $0) }
    carriedExtraData = scenario.extraData
  }
}
