import Foundation

/// Commit-time canonical-output-field enforcement, split out of the main
/// `ScenarioValidator.swift` so each file stays under the `file_length` /
/// `type_body_length` caps.
///
/// `nonisolated` on the extension is load-bearing: `ScenarioValidator` is a
/// `nonisolated` Engine type, but a sibling-file `extension` inherits
/// `MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION` unless annotated, which
/// would break the synchronous calls from `validateForCommit` in the main file
/// (`.claude/rules/swift-isolation.md` Pattern 3).
nonisolated extension ScenarioValidator {

  /// Enforces ``ScenarioConventions/primaryField(for:)`` and
  /// ``ScenarioConventions/thoughtField(for:)`` for LLM phases, recursing
  /// into `conditional` branches so violations inside `then:` / `else:`
  /// sub-phases are caught at commit time. Code phases are exempt (the
  /// conventions tables return `nil` and the per-phase checks return
  /// early). Termination is trivial: `.conditional` is depth-1 by both
  /// `validateConditionalPhase` and the YAML parser
  /// (`ScenarioLoader.mapPhase`), so the recursion bottoms out after one
  /// descent.
  ///
  /// Module-internal (not `private`) so `validateForCommit` in the main file
  /// can call it.
  func validateCanonicalFields(_ scenario: Scenario) throws {
    for (index, phase) in scenario.phases.enumerated() {
      let label = "Phase \(index + 1)"
      try validateCanonicalFields(in: phase, label: label)
      // Mirror `validateBranch`'s label shape so sub-phase errors carry
      // the parent's "(conditional)" annotation — keeps a single mental
      // template across all branch-related validator messages.
      let parentLabel = "\(label) (\(phase.type.rawValue))"
      try validateBranchCanonicalFields(
        phase.thenPhases, parentLabel: parentLabel, branchLabel: "then")
      try validateBranchCanonicalFields(
        phase.elsePhases, parentLabel: parentLabel, branchLabel: "else")
    }
  }

  /// Runs both canonical-field checks (primary + thought) for one phase.
  private func validateCanonicalFields(in phase: Phase, label: String) throws {
    try validateCanonicalPrimaryField(in: phase, label: label)
    try validateCanonicalThoughtField(in: phase, label: label)
  }

  private func validateCanonicalPrimaryField(in phase: Phase, label: String) throws {
    guard let canonical = ScenarioConventions.primaryField(for: phase.type) else {
      return
    }
    let schema = phase.outputSchema ?? [:]
    if schema[canonical] == nil {
      throw validationError(
        String(localized: "%@ (%@) requires field '%@' in output."),
        label, phase.type.rawValue, canonical)
    }
  }

  /// Enforces ``ScenarioConventions/thoughtField(for:)``: when a phase
  /// declares any known secondary key (``OutputSchema/knownSecondaryKeys``
  /// — `inner_thought` / `reason`), it must be the phase's canonical
  /// thought field (vote→`reason`, speak*/choose→`inner_thought`). The
  /// secondary field is optional, so a phase that declares none passes.
  ///
  /// Checks *every* declared known-secondary key rather than only
  /// ``OutputSchema/thoughtFieldName``'s priority pick, so a stray `reason`
  /// alongside a canonical `inner_thought` is still caught. This is what
  /// keeps the live-streaming THINKING source
  /// (``OutputSchema/thoughtFieldName``, schema-driven) and the committed
  /// source (``TurnOutput/secondaryText(for:)``, phase-hardcoded) reading
  /// the same key — a choose authored with `reason` streamed live but went
  /// blank on commit (#760).
  private func validateCanonicalThoughtField(in phase: Phase, label: String) throws {
    guard let canonical = ScenarioConventions.thoughtField(for: phase.type) else {
      return
    }
    let schema = phase.outputSchema ?? [:]
    for key in OutputSchema.knownSecondaryKeys
    where schema[key] != nil && key != canonical {
      throw validationError(
        String(localized: "%@ (%@) secondary field must be '%@', not '%@'."),
        label, phase.type.rawValue, canonical, key)
    }
  }

  private func validateBranchCanonicalFields(
    _ phases: [Phase]?, parentLabel: String, branchLabel: String
  ) throws {
    guard let phases else { return }
    for (subIndex, subPhase) in phases.enumerated() {
      try validateCanonicalFields(
        in: subPhase, label: "\(parentLabel) \(branchLabel)[\(subIndex + 1)]")
    }
  }
}

/// File-scope copy of the main file's `validationError`, kept `private` so it
/// does not collide with the same-named helpers in `ScenarioValidator.swift`
/// and `ScenarioLoader.swift` at module scope. Same Form-B i18n contract — the
/// `String(localized:)` literal stays a single extractable key
/// (see `.claude/rules/i18n.md`).
nonisolated private func validationError(
  _ format: String, _ arguments: CVarArg...
) -> SimulationError {
  .scenarioValidationFailed(String(format: format, arguments: arguments))
}
