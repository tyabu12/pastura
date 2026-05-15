import Foundation

/// A complete scenario definition parsed from YAML.
///
/// This is the pure domain model representing a scenario's structure.
/// It does not include persistence metadata (id, isPreset, timestamps) —
/// those belong to `ScenarioRecord` in the Data layer.
///
/// Scenarios are parsed from YAML via `ScenarioLoader` in the Engine layer
/// using manual mapping (`Yams.load()` → `[String: Any]`).
nonisolated public struct Scenario: Codable, Sendable, Equatable {
  /// Accepted values for ``language`` (D1) and ``simulationLanguage`` (D5).
  ///
  /// Single source of truth — both ``ScenarioLoader`` (YAML path) and
  /// ``ScenarioValidator`` (programmatic-construction path) gate against
  /// this set. Adding a third language (Phase 3+) is new-ADR scope per
  /// ADR-010 Out-of-Scope; extending this set is the first concrete step
  /// but never sufficient on its own.
  public static let acceptedLanguages: Set<String> = ["ja", "en"]

  /// Unique identifier for the scenario (from YAML `id` field).
  public let id: String

  /// Human-readable scenario name.
  public let name: String

  /// Brief description of what this scenario simulates.
  public let description: String

  /// Scenario authoring language: ISO 639-1 lowercase code (`"ja"` or `"en"`).
  ///
  /// Drives Engine output language at runtime (prompt templates, scoring
  /// summaries, handler default fallbacks) via per-site `switch
  /// scenario.language` dispatch. Validator enforces `{ja, en}` at load
  /// time; absence is rejected by `ScenarioLoader` (no backward-compat
  /// fill). See ADR-010 D1 / D7.
  public let language: String

  /// Optional Engine override language for cross-language simulation.
  ///
  /// When non-nil, the Engine reads from this instead of ``language`` —
  /// enabling "run an `en` scenario on a `ja` device with
  /// `simulation_language: ja`." Resolved via ``engineLanguage`` at every
  /// Engine site; never read directly outside that single resolve point.
  /// See ADR-010 D5.
  public let simulationLanguage: String?

  /// Engine-consumer resolver for cross-language simulation (ADR-010 D6
  /// row 1). Returns ``simulationLanguage`` when set, falling through to
  /// ``language`` otherwise.
  ///
  /// **Do not use as a generic resolver.** D6 defines four consumer rows,
  /// each with its own resolver:
  ///
  /// - **Engine** (prompt / scoring / default text): `engineLanguage`
  ///   (this property)
  /// - **New scenario creation seed** (Editor): `LocaleResolver.deviceDefault()`
  /// - **Preset / gallery initial selection** (picker): `LocaleResolver.deviceDefault()`
  /// - **UI shell** (`Localizable.xcstrings`): `Bundle.main.preferredLocalizations`
  ///
  /// UI / Editor / Picker callsites **MUST** continue using their own D6
  /// resolvers; reading ``engineLanguage`` from those layers silently
  /// bypasses device-locale priority. Two Engine-adjacent sites also
  /// stay on ``language`` (authoring axis), not ``engineLanguage``
  /// (runtime axis):
  ///
  /// - ``ScenarioValidator`` validates the authoring `language` field.
  /// - ``ScenarioSerializer`` writes the authoring `language` back to YAML.
  ///
  /// `scripts/check_engine_language_axis.sh` enforces the Engine-side
  /// boundary in CI; cross-layer misuse is caught by code review.
  public var engineLanguage: String { simulationLanguage ?? language }

  /// Expected number of agents. Must match `personas.count`.
  public let agentCount: Int

  /// Number of rounds to execute.
  public let rounds: Int

  /// Shared context injected into every agent's system prompt.
  public let context: String

  /// Agent persona definitions.
  public let personas: [Persona]

  /// Ordered list of phases executed each round.
  public let phases: [Phase]

  /// Scenario-specific data beyond the standard fields.
  ///
  /// Holds arbitrary top-level YAML fields that phase handlers access at runtime.
  /// For example, bokete's `topics` (string array) or word wolf's `words`
  /// (array of dictionaries). The `assign` phase references keys here via its
  /// `source` field. Empty if the scenario has no extra data.
  public let extraData: [String: AnyCodableValue]

  public init(
    id: String,
    name: String,
    description: String,
    language: String,
    simulationLanguage: String? = nil,
    agentCount: Int,
    rounds: Int,
    context: String,
    personas: [Persona],
    phases: [Phase],
    extraData: [String: AnyCodableValue] = [:]
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.language = language
    self.simulationLanguage = simulationLanguage
    self.agentCount = agentCount
    self.rounds = rounds
    self.context = context
    self.personas = personas
    self.phases = phases
    self.extraData = extraData
  }
}
