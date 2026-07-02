import Foundation
import Testing

@testable import Pastura

/// Mechanical recurrence guard for the #890 failure class: a `{token}` used
/// in a bundled preset's prompt / summarize-template that **no** handler
/// injects, so it leaks literally into the LLM prompt.
///
/// For every bundled preset, extracts each `{token}` from prompt / template
/// fields (recursing into `conditional` sub-phases) and asserts it is
/// covered by one of:
///   - ``PromptPlaceholders/engineSupplied`` (the run-time-injected set), or
///   - a per-persona `assigned_<name>` key (AssignHandler's per-agent write), or
///   - an `event_inject` phase's `eventVariable` (defaulting to `current_event`).
///
/// This guard is phase-context-blind by design — see the doc-comment on
/// `PromptPlaceholders`. It would have caught #890 (`{assigned_word}` ∉
/// `engineSupplied` before the fix). It complements — does not replace —
/// `AssignedPlaceholderInjectionTests`, which proves the injection is
/// actually wired (this test would still pass if `injectAssigned` were
/// deleted, as long as `assigned_word` stayed in the set).
@Suite(.timeLimit(.minutes(1)))
struct BundledPresetPlaceholderCoverageTests {

  /// Anchors `Bundle(for:)` on the test module so preset lookup falls through
  /// to the test target's bundle before `Bundle.main` (the UI runner).
  private final class Anchor {}

  private func loadPreset(_ filename: String) throws -> Scenario {
    let bundle = Bundle(for: Anchor.self)
    guard
      let url = bundle.url(forResource: filename, withExtension: "yaml")
        ?? Bundle.main.url(forResource: filename, withExtension: "yaml")
    else {
      Issue.record("Preset YAML '\(filename).yaml' not found in test or app bundle")
      throw CocoaError(.fileNoSuchFile)
    }
    let yaml = try String(contentsOf: url, encoding: .utf8)
    return try ScenarioLoader().load(yaml: yaml)
  }

  /// Extracts every `{token}` (letter/underscore-led identifier) from a string.
  private func placeholders(in text: String) -> Set<String> {
    // Deliberately narrow: only `{ident}` shapes. Values are the runtime
    // variable keys `expandTemplate` substitutes.
    let pattern = #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var tokens: Set<String> = []
    for match in regex.matches(in: text, range: range) {
      if let tokenRange = Range(match.range(at: 1), in: text) {
        tokens.insert(String(text[tokenRange]))
      }
    }
    return tokens
  }

  /// Walks a phase and its `conditional` sub-phases, collecting all prompt /
  /// template placeholder tokens.
  private func collectTokens(_ phase: Phase) -> Set<String> {
    var tokens: Set<String> = []
    if let prompt = phase.prompt { tokens.formUnion(placeholders(in: prompt)) }
    if let template = phase.template { tokens.formUnion(placeholders(in: template)) }
    for sub in (phase.thenPhases ?? []) + (phase.elsePhases ?? []) {
      tokens.formUnion(collectTokens(sub))
    }
    return tokens
  }

  /// Walks a phase and its `conditional` sub-phases, collecting the event
  /// variable each `event_inject` writes (defaulting to `current_event`).
  private func collectEventVariables(_ phase: Phase) -> Set<String> {
    var vars: Set<String> = []
    if phase.type == .eventInject {
      vars.insert(phase.eventVariable ?? "current_event")
    }
    for sub in (phase.thenPhases ?? []) + (phase.elsePhases ?? []) {
      vars.formUnion(collectEventVariables(sub))
    }
    return vars
  }

  @Test func everyBundledPresetPlaceholderIsSupplied() throws {
    for filename in PresetLoader.presetFileNames {
      let scenario = try loadPreset(filename)

      let personaKeys = Set(scenario.personas.map { "assigned_\($0.name)" })
      let eventVars = scenario.phases.reduce(into: Set<String>()) {
        $0.formUnion(collectEventVariables($1))
      }
      let allowed = PromptPlaceholders.engineSupplied
        .union(personaKeys)
        .union(eventVars)

      let used = scenario.phases.reduce(into: Set<String>()) {
        $0.formUnion(collectTokens($1))
      }

      for token in used where !allowed.contains(token) {
        // Build the message as a String first: Issue.record expects a Comment,
        // so an inline `"..." + "..."` mis-resolves `+` to the Sequence overload.
        let message: String =
          "Preset '\(filename)' references {\(token)} which no handler supplies. "
          + "Add it to PromptPlaceholders.engineSupplied (and wire injection) "
          + "or remove it from the preset."
        Issue.record(Comment(rawValue: message))
      }
    }
  }
}
