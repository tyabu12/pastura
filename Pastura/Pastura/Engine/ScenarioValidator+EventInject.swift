import Foundation

/// `event_inject` phase shape-checks, split out of `ScenarioValidator` to
/// keep the main type under swiftlint's file / type / function length caps.
///
/// `nonisolated` on the extension is load-bearing: `ScenarioValidator` is a
/// `nonisolated` Engine type, and a plain sibling-file `extension` would
/// inherit default-MainActor isolation and break the nonisolated callers in
/// the main file (see `.claude/rules/swift-isolation.md` Pattern 3).
nonisolated extension ScenarioValidator {

  /// Shared shape-check for event_inject phases, callable from both the
  /// top-level path and from inside a conditional branch.
  ///
  /// Enforces:
  /// - `source` must be present and non-empty (the handler's no-op
  ///   fallback exists for the case where extraData lookup fails at
  ///   runtime, but a curator who wrote `event_inject` clearly meant
  ///   to fire — failing fast at validation is friendlier).
  /// - `extraData[source]` must be `.array` (a list of strings) or
  ///   `.arrayOfDictionaries` (a list of `{ text, favors }` mappings, #931 —
  ///   each entry needs a non-empty `text`; `favors` is optional). `.string`
  ///   / `.dictionary` are rejected; the error message points at the
  ///   workaround so curators don't get stuck.
  /// - `probability` (when set) must lie in `[0.0, 1.0]`. The handler
  ///   would still produce well-defined behavior outside this range
  ///   (`< 0` never fires, `>= 1.0` always fires), but a curator who
  ///   wrote `probability: 1.5` almost certainly mistyped — surfacing
  ///   it early is friendlier than silent over-fire.
  func validateEventInjectShape(
    _ phase: Phase, label: String, scenario: Scenario
  ) throws {
    let sourceKey = (phase.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sourceKey.isEmpty else {
      throw validationError(
        String(
          localized:
            "%@: missing 'source'. event_inject requires a 'source' key naming a top-level YAML field that lists the event strings."
        ),
        label)
    }
    guard let sourceValue = scenario.extraData[sourceKey] else {
      throw validationError(
        String(
          localized:
            "%@: source '%@' not found in scenario data. Add a top-level '%@' field to the scenario YAML."
        ),
        label, sourceKey, sourceKey)
    }
    switch sourceValue {
    case .array(let entries):
      // Empty array silently produces probability-miss-equivalent output
      // at runtime (handler writes "" and emits .eventInjected(nil)), which
      // a curator cannot distinguish from a string of unlucky rolls. Reject
      // early so the misconfiguration surfaces at scenario load.
      guard !entries.isEmpty else {
        throw validationError(
          String(
            localized:
              "%@: source '%@' is empty. event_inject requires at least one string in the list; for a single fixed event use ['only_event']."
          ),
          label, sourceKey)
      }
    case .arrayOfDictionaries(let entries):
      try validateDictEventEntries(entries, sourceKey: sourceKey, label: label)
    case .string, .dictionary:
      throw validationError(
        String(
          localized:
            "%@: source '%@' must be a list of event strings or {text, favors} mappings; for a single fixed event use ['only_event']."
        ),
        label, sourceKey)
    }
    try validateEventProbability(phase.probability, label: label)
  }

  /// Dict-shaped events (`{ text, favors }`, #931). Same empty-list rejection
  /// as the string shape, plus each entry must carry a non-empty `text` — an
  /// entry without it injects "" (a silent no-op). `favors` is optional (an
  /// untagged entry simply scores no reward).
  private func validateDictEventEntries(
    _ entries: [[String: String]], sourceKey: String, label: String
  ) throws {
    guard !entries.isEmpty else {
      throw validationError(
        String(
          localized:
            "%@: source '%@' is empty. event_inject requires at least one event in the list; for a single fixed event use ['only_event']."
        ),
        label, sourceKey)
    }
    for entry in entries
    where (entry["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw validationError(
        String(
          localized:
            "%@: source '%@' has an event entry missing a non-empty 'text'. Dict-shaped events require 'text' (and may add 'favors')."
        ),
        label, sourceKey)
    }
  }

  /// `probability` (when set) must lie in `[0.0, 1.0]` — see the type-level
  /// doc on `validateEventInjectShape`.
  private func validateEventProbability(_ probability: Double?, label: String) throws {
    guard let probability else { return }
    guard (0.0...1.0).contains(probability) else {
      throw validationError(
        String(
          localized: "%@: probability %@ is out of range. Must be between 0.0 and 1.0 inclusive."),
        label, String(probability))
    }
  }
}

// File-private copy so this sibling extension does not depend on the main
// file's same-named helper, mirroring `ScenarioValidator+CanonicalFields.swift`.
// A module-scope `internal` version would collide with `ScenarioLoader`'s
// same-named helper.
nonisolated private func validationError(
  _ format: String, _ arguments: CVarArg...
) -> SimulationError {
  .scenarioValidationFailed(String(format: format, arguments: arguments))
}
