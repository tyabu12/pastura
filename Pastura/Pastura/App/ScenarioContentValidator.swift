import Foundation

/// Rejects scenario content whose user-authored text fields contain
/// patterns from the shared blocklist.
///
/// Input-side counterpart to ``ContentFilter`` in ADR-005's
/// defense-in-depth model. Invoked from MainActor ViewModels
/// (`ImportViewModel`, `ScenarioEditorViewModel`) after structural
/// validation succeeds. Unlike ``ContentFilter``, findings are surfaced
/// as user-facing messages the author can act on — the validator never
/// rewrites its input, and no message echoes the matched term (ADR-005
/// §4.7).
///
/// MainActor-bound per ADR-005 §4.6 (uses the project-default
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). All callers today are
/// MainActor ViewModels on user-input paths; if an off-main caller
/// materialises, promote to `nonisolated + Sendable` as a local change.
final class ScenarioContentValidator {
  private let blockedPatterns: [String]

  /// Creates a validator with the given blocklist.
  ///
  /// - Parameter blockedPatterns: Words/phrases to reject at authoring
  ///   time. Matched case- and diacritic-insensitively. Defaults to the
  ///   input partition of the shared bundled blocklist (excludes the
  ///   `violence` category per ADR-005 §10.1).
  init(blockedPatterns: [String] = ContentBlocklist.inputPatterns) {
    self.blockedPatterns = blockedPatterns
  }

  /// Walks all user-authored text fields of the scenario and returns
  /// one user-facing message per field that contains a blocked pattern.
  ///
  /// Walk order mirrors ADR-005 §4.3's target-fields table:
  /// scenario → personas → phases, recursing into `thenPhases` /
  /// `elsePhases` for `conditional` phases. The recursion walks
  /// defensively beyond the depth-1 rule that `ScenarioValidator`
  /// structurally enforces.
  func validate(_ scenario: Scenario) -> [String] {
    var findings: [String] = []

    if containsBlockedPattern(scenario.name) {
      findings.append(
        String(localized: "Scenario name contains a term that is not allowed")
      )
    }
    if containsBlockedPattern(scenario.description) {
      findings.append(
        String(localized: "Scenario description contains a term that is not allowed")
      )
    }

    for (index, persona) in scenario.personas.enumerated() {
      findings.append(contentsOf: personaFindings(persona, index: index))
    }

    for (index, phase) in scenario.phases.enumerated() {
      findings.append(contentsOf: phaseFindings(phase, position: "\(index + 1)"))
    }

    return findings
  }

  // MARK: - Per-field API for inline editor sheets (#261)

  /// Per-field findings for inline validation in `PersonaEditorSheet`.
  ///
  /// Each property is either `nil` (clean) or a localized error message.
  /// Messages are intentionally context-free — they do not interpolate
  /// sibling field values, so when both `name` and `description` contain
  /// blocked patterns, neither message echoes the matched term
  /// (ADR-005 §4.7).
  struct PersonaFindings: Sendable {
    let name: String?
    let description: String?
    var hasIssue: Bool { name != nil || description != nil }
  }

  /// Per-field findings for inline validation in `PhaseEditorSheet`.
  ///
  /// Same context-free contract as ``PersonaFindings``: messages do not
  /// interpolate other phase fields. Per-field, per-tap validation is
  /// scoped to the three blockable content fields the scenario-level
  /// walk also covers (ADR-005 §4.3).
  struct PhaseFindings: Sendable {
    let prompt: String?
    let template: String?
    let condition: String?
    var hasIssue: Bool { prompt != nil || template != nil || condition != nil }
  }

  /// Validates a single persona's text fields for inline editor feedback.
  ///
  /// Empty strings are skipped — mirrors ``EditablePhase.toPhase()``'s
  /// empty→nil convention so authors don't see errors for fields they
  /// have not typed in. Returned messages are context-free; see
  /// ``PersonaFindings`` doc-comment.
  func validate(personaName name: String, description: String) -> PersonaFindings {
    PersonaFindings(
      name: shouldFlag(name)
        ? String(localized: "Name contains a term that is not allowed")
        : nil,
      description: shouldFlag(description)
        ? String(localized: "Description contains a term that is not allowed")
        : nil
    )
  }

  /// Validates a single phase's content text fields for inline editor feedback.
  ///
  /// Empty strings are skipped. Callers are expected to pass only the
  /// fields the active phase type exposes in the UI — fields the user
  /// cannot edit at this moment shouldn't surface errors here. The
  /// scenario-level ``validate(_:)`` walk remains the backstop for
  /// residual blocked text in fields hidden by a type switch.
  func validate(
    phasePrompt prompt: String,
    template: String,
    condition: String
  ) -> PhaseFindings {
    PhaseFindings(
      prompt: shouldFlag(prompt)
        ? String(localized: "Prompt contains a term that is not allowed")
        : nil,
      template: shouldFlag(template)
        ? String(localized: "Template contains a term that is not allowed")
        : nil,
      condition: shouldFlag(condition)
        ? String(localized: "Condition contains a term that is not allowed")
        : nil
    )
  }

  // MARK: - Private

  private func shouldFlag(_ text: String) -> Bool {
    !text.isEmpty && containsBlockedPattern(text)
  }

  private func personaFindings(_ persona: Persona, index: Int) -> [String] {
    var findings: [String] = []
    let position = index + 1
    let nameIsClean = !containsBlockedPattern(persona.name)

    if !nameIsClean {
      findings.append(
        String(localized: "Persona \(position) name contains a term that is not allowed")
      )
    }
    if containsBlockedPattern(persona.description) {
      // Why: ADR-005 §4.7 requires findings to never echo the matched term.
      // When the name itself is a blocked term, interpolating it into the
      // description message would leak the pattern — fall back to positional
      // form instead.
      if nameIsClean {
        findings.append(
          String(
            localized:
              "Persona '\(persona.name)' description contains a term that is not allowed"
          )
        )
      } else {
        findings.append(
          String(
            localized: "Persona \(position) description contains a term that is not allowed"
          )
        )
      }
    }
    return findings
  }

  private func phaseFindings(_ phase: Phase, position: String) -> [String] {
    var findings: [String] = []

    if let prompt = phase.prompt, containsBlockedPattern(prompt) {
      findings.append(
        String(localized: "Phase \(position) prompt contains a term that is not allowed")
      )
    }
    if let template = phase.template, containsBlockedPattern(template) {
      findings.append(
        String(localized: "Phase \(position) template contains a term that is not allowed")
      )
    }
    if let condition = phase.condition, containsBlockedPattern(condition) {
      findings.append(
        String(localized: "Phase \(position) condition contains a term that is not allowed")
      )
    }

    if let thenPhases = phase.thenPhases {
      for (index, subPhase) in thenPhases.enumerated() {
        findings.append(
          contentsOf: phaseFindings(subPhase, position: "\(position).then.\(index + 1)")
        )
      }
    }
    if let elsePhases = phase.elsePhases {
      for (index, subPhase) in elsePhases.enumerated() {
        findings.append(
          contentsOf: phaseFindings(subPhase, position: "\(position).else.\(index + 1)")
        )
      }
    }

    return findings
  }

  private func containsBlockedPattern(_ text: String) -> Bool {
    blockedPatterns.contains { pattern in
      text.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}
