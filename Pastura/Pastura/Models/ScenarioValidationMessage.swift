import Foundation

/// A parameter-carrying description of a scenario load / validation failure.
///
/// The Engine run path (``ScenarioValidator`` + extensions, ``ScenarioLoader``)
/// throws these instead of building user-facing strings inline: each case is a
/// **portable structured payload** (enum case + typed args, no Foundation), and
/// ``localized`` is the single **platform-specific rendering leaf** that turns a
/// case into the display string.
///
/// This is the message-model split for the KMP Phase 3.0 Engine port (issue
/// #501, Stage 0 / S0.1): the cases move to Kotlin `commonMain` 1:1 as a sealed
/// class, while `localized` becomes an `expect`/`actual` leaf. Concretely it
/// removes `CVarArg` **and** `String(format:)` **and** `String(localized:)` —
/// all Foundation/ObjC-isms — from the Engine files, which is the real
/// portability delta, not merely relocating the `String(localized:)` token.
///
/// The rendered text is byte-identical to the pre-refactor Engine literals so
/// `Localizable.xcstrings` keys are unchanged. Callers wrap the rendered string
/// in ``SimulationError/scenarioValidationFailed(_:)`` (unchanged payload type —
/// it is shared by many out-of-scope plain-literal throwers).
nonisolated public enum ScenarioValidationMessage: Sendable {
  // MARK: Language membership (shared: ScenarioValidator + ScenarioLoader)
  case languageNotAccepted(allowed: String, got: String)
  case simulationLanguageNotAccepted(allowed: String, got: String)
  case simulationLanguageYAMLNotAccepted(allowed: String, got: String)

  // MARK: Execution limits (ScenarioValidator)
  case agentCountBelowMinimum(Int)
  case agentCountExceedsMaximum(Int)
  case personaCountMismatch(personaCount: Int, agentCount: Int)
  case roundCountExceedsMaximum(Int)
  case logWindowBelowMinimum(Int)
  case estimatedInferencesExceedsMaximum(Int)
  case highInferenceCount(Int)

  // MARK: Conditional-phase shape (ScenarioValidator; nestedConditional shared with ScenarioLoader)
  case conditionalMissingIf(label: String)
  case conditionalEmptyBranches(label: String)
  case nestedConditionalNotAllowed(label: String)
  case branchNestedConditional(label: String)
  case branchReflectNotAllowed(label: String)
  case branchWhisperNotAllowed(label: String)
  case branchRelationshipUpdateNotAllowed(label: String)

  // MARK: Canonical / required output fields (shared: ScenarioValidator + +CanonicalFields)
  case requiresOutputField(label: String, type: String, field: String)
  case secondaryFieldMismatch(label: String, type: String, canonical: String, key: String)
  case relationshipUpdateMissingRule(label: String, type: String)

  // MARK: Assign-phase source shape (ScenarioValidator; sourceNotFound shared with +EventInject)
  case sourceNotFound(label: String, source: String)
  case assignSourceGroupedForAll(label: String, source: String)
  case assignSourceNotGroupedForRandomOne(label: String, source: String)

  // MARK: Structural mapping (ScenarioLoader)
  case invalidYAMLFormat
  case missingRequiredField(label: String, key: String)
  case fieldWrongType(label: String, key: String, expected: String, got: String)
  case fieldNotDoubleOrInt(label: String, key: String, got: String)
  case agentsPersonasCountMismatch(agentCount: Int, personaCount: Int)
  case invalidTarget(label: String, value: String)
  case invalidPairing(label: String, value: String)
  case invalidLogic(label: String, value: String, allowed: String)
  case actionDeltasNotDict(label: String, got: String)
  case actionDeltasValueNotInt(label: String, key: String, got: String)
  case phaseMissingType(label: String)
  case phaseInvalidType(label: String, value: String)
  case outputNotDict(label: String, got: String)
  case outputValueNotString(label: String, key: String, got: String)
  case branchNotArray(label: String, branch: String)
  case extraDataArrayOfDictNotString(key: String)
  case extraDataMixedArray(key: String)
  case extraDataDictNotString(key: String)
  case extraDataUnsupportedType(key: String, got: String, shapes: String)

  // MARK: event_inject shape (+EventInject)
  case eventInjectMissingSource(label: String)
  case eventInjectSourceEmptyStrings(label: String, source: String)
  case eventInjectSourceWrongShape(label: String, source: String)
  case eventInjectSourceEmptyEvents(label: String, source: String)
  case eventInjectEntryMissingText(label: String, source: String)
  case eventInjectProbabilityOutOfRange(label: String, probability: String)

  // MARK: Output field-name validation (+OutputFieldNames)
  case outputFieldNameInvalid(label: String, name: String)
}

// `nonisolated` on the extension is load-bearing: the enum is a `nonisolated`
// Models type, but a sibling `extension` inherits the project's default
// MainActor isolation unless annotated (`.claude/rules/swift-isolation.md`
// Pattern 3), which would break the synchronous `nonisolated` Engine callers.
nonisolated extension ScenarioValidationMessage {

  /// Renders the case to its user-facing string.
  ///
  /// The **only** Foundation-touching member — the KMP `expect`/`actual` leaf
  /// (see the type doc). Literals are byte-identical to the pre-refactor Engine
  /// callsites so `Localizable.xcstrings` keys stay stable. No-arg cases use
  /// `String(localized:)` directly (never `String(format:)`, which would
  /// misread a stray `%` in a future literal). `%lld` args stay `Int` — passing
  /// `Int` to `%lld` on 64-bit iOS matches the pre-refactor `CVarArg` behavior.
  public var localized: String {
    switch self {
    case .languageNotAccepted(let allowed, let got):
      return String(
        format: String(localized: "Scenario: field 'language' must be one of {%@}, got '%@'"),
        allowed, got)
    case .simulationLanguageNotAccepted(let allowed, let got):
      return String(
        format: String(
          localized: "Scenario: field 'simulationLanguage' must be one of {%@} or nil, got '%@'"),
        allowed, got)
    case .simulationLanguageYAMLNotAccepted(let allowed, let got):
      return String(
        format: String(
          localized: "Scenario: field 'simulation_language' must be one of {%@} or absent, got '%@'"
        ),
        allowed, got)
    case .agentCountBelowMinimum(let count):
      return String(
        format: String(localized: "Agent count (%lld) is below minimum of 2"), count)
    case .agentCountExceedsMaximum(let count):
      return String(
        format: String(localized: "Agent count (%lld) exceeds maximum of 10"), count)
    case .personaCountMismatch(let personaCount, let agentCount):
      return String(
        format: String(localized: "Persona count (%lld) does not match agent count (%lld)"),
        personaCount, agentCount)
    case .roundCountExceedsMaximum(let rounds):
      return String(
        format: String(localized: "Round count (%lld) exceeds maximum of 30"), rounds)
    case .logWindowBelowMinimum(let window):
      return String(
        format: String(localized: "Log window (%lld) must be at least 1"), window)
    case .estimatedInferencesExceedsMaximum(let estimated):
      return String(
        format: String(localized: "Estimated inferences (%lld) exceeds maximum of 100"), estimated)
    case .highInferenceCount(let estimated):
      return String(
        format: String(
          localized: "High inference count (%lld). Simulation may take several minutes."),
        estimated)
    case .conditionalMissingIf(let label):
      return String(
        format: String(localized: "%@: missing or empty 'if' expression."), label)
    case .conditionalEmptyBranches(let label):
      return String(
        format: String(localized: "%@: must have at least one sub-phase in 'then' or 'else'."),
        label)
    case .nestedConditionalNotAllowed(let label):
      return String(
        format: String(
          localized:
            "%@: nested 'conditional' inside another conditional is not allowed (depth-1 rule)."),
        label)
    case .branchNestedConditional(let label):
      return String(
        format: String(
          localized: "%@ is another conditional, which is not allowed (depth-1 rule)."),
        label)
    case .branchReflectNotAllowed(let label):
      return String(
        format: String(
          localized: "%@ is a reflect phase, which is not allowed inside a conditional."),
        label)
    case .branchWhisperNotAllowed(let label):
      return String(
        format: String(
          localized: "%@ is a whisper phase, which is not allowed inside a conditional."),
        label)
    case .branchRelationshipUpdateNotAllowed(let label):
      return String(
        format: String(
          localized:
            "%@ is a relationship_update phase, which is not allowed inside a conditional."),
        label)
    case .requiresOutputField(let label, let type, let field):
      return String(
        format: String(localized: "%@ (%@) requires field '%@' in output."), label, type, field)
    case .secondaryFieldMismatch(let label, let type, let canonical, let key):
      return String(
        format: String(localized: "%@ (%@) secondary field must be '%@', not '%@'."),
        label, type, canonical, key)
    case .relationshipUpdateMissingRule(let label, let type):
      return String(
        format: String(
          localized:
            "%@ (%@) requires at least one affinity rule: 'vote_against' and/or 'action_deltas'."),
        label, type)
    case .sourceNotFound(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' not found in scenario data. Add a top-level '%@' field to the scenario YAML."
        ),
        label, source, source)
    case .assignSourceGroupedForAll(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' contains grouped values (e.g., majority/minority pairs). Use target: random_one to distribute these. Use target: all only for a flat list of strings or a single string."
        ),
        label, source)
    case .assignSourceNotGroupedForRandomOne(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' must be a list of grouped values (e.g., majority/minority pairs) when target is random_one."
        ),
        label, source)
    case .invalidYAMLFormat:
      return String(localized: "Invalid YAML format")
    case .missingRequiredField(let label, let key):
      return String(
        format: String(localized: "%@: missing required field '%@'"), label, key)
    case .fieldWrongType(let label, let key, let expected, let got):
      return String(
        format: String(localized: "%@: field '%@' must be %@, got %@"), label, key, expected, got)
    case .fieldNotDoubleOrInt(let label, let key, let got):
      return String(
        format: String(localized: "%@: field '%@' must be Double or Int, got %@"), label, key, got)
    case .agentsPersonasCountMismatch(let agentCount, let personaCount):
      return String(
        format: String(localized: "agents (%lld) does not match personas count (%lld)"),
        agentCount, personaCount)
    case .invalidTarget(let label, let value):
      return String(
        format: String(localized: "%@ has invalid target: '%@'. Use 'all' or 'random_one'."),
        label, value)
    case .invalidPairing(let label, let value):
      return String(
        format: String(localized: "%@ has invalid pairing: '%@'. Use 'round_robin'."), label, value)
    case .invalidLogic(let label, let value, let allowed):
      return String(
        format: String(localized: "%@ has invalid logic: '%@'. Expected one of: %@."),
        label, value, allowed)
    case .actionDeltasNotDict(let label, let got):
      return String(
        format: String(
          localized: "%@: field 'action_deltas' must be a dictionary of Int values, got %@"),
        label, got)
    case .actionDeltasValueNotInt(let label, let key, let got):
      return String(
        format: String(localized: "%@: action_deltas value for '%@' must be Int, got %@"),
        label, key, got)
    case .phaseMissingType(let label):
      return String(format: String(localized: "%@ missing 'type'"), label)
    case .phaseInvalidType(let label, let value):
      return String(
        format: String(localized: "%@ has invalid type: '%@'"), label, value)
    case .outputNotDict(let label, let got):
      return String(
        format: String(
          localized: "%@: field 'output' must be a dictionary of String values, got %@"),
        label, got)
    case .outputValueNotString(let label, let key, let got):
      return String(
        format: String(localized: "%@: output schema value for '%@' must be String, got %@"),
        label, key, got)
    case .branchNotArray(let label, let branch):
      return String(
        format: String(localized: "%@: '%@' must be an array of phase objects"), label, branch)
    case .extraDataArrayOfDictNotString(let key):
      return String(
        format: String(
          localized:
            "Top-level field '%@': array-of-dict values must all be String. Quote non-string values (e.g. `majority: \"1\"`)."
        ),
        key)
    case .extraDataMixedArray(let key):
      return String(
        format: String(
          localized:
            "Top-level field '%@': mixed-type arrays are not supported. Use a pure [String] or [[String: String]]."
        ),
        key)
    case .extraDataDictNotString(let key):
      return String(
        format: String(
          localized:
            "Top-level field '%@': dictionary values must all be String. Quote non-string values."),
        key)
    case .extraDataUnsupportedType(let key, let got, let shapes):
      return String(
        format: String(
          localized: "Top-level field '%@' has unsupported type %@. Supported shapes: %@."),
        key, got, shapes)
    case .eventInjectMissingSource(let label):
      return String(
        format: String(
          localized:
            "%@: missing 'source'. event_inject requires a 'source' key naming a top-level YAML field that lists the event strings."
        ),
        label)
    case .eventInjectSourceEmptyStrings(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' is empty. event_inject requires at least one string in the list; for a single fixed event use ['only_event']."
        ),
        label, source)
    case .eventInjectSourceWrongShape(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' must be a list of event strings or {text, favors} mappings; for a single fixed event use ['only_event']."
        ),
        label, source)
    case .eventInjectSourceEmptyEvents(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' is empty. event_inject requires at least one event in the list; for a single fixed event use ['only_event']."
        ),
        label, source)
    case .eventInjectEntryMissingText(let label, let source):
      return String(
        format: String(
          localized:
            "%@: source '%@' has an event entry missing a non-empty 'text'. Dict-shaped events require 'text' (and may add 'favors')."
        ),
        label, source)
    case .eventInjectProbabilityOutOfRange(let label, let probability):
      return String(
        format: String(
          localized: "%@: probability %@ is out of range. Must be between 0.0 and 1.0 inclusive."),
        label, probability)
    case .outputFieldNameInvalid(let label, let name):
      return String(
        format: String(
          localized:
            "%@: output field name '%@' must be an ASCII identifier (letters, digits, and underscore, not starting with a digit or underscore). Agent text values may be any language."
        ),
        label, name)
    }
  }
}
