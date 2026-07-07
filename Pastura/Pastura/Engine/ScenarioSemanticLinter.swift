import Foundation

/// Severity tier for a ``LintFinding`` — the three-tier boundary from ADR-022.
///
/// - `error`: statically provable no-op or guaranteed-wrong semantics, with no
///   deliberate-authoring reading → **blocking** (treated like a
///   ``ScenarioValidator`` error at the commit and run gates).
/// - `warning`: probably unintended, but a deliberate reading exists → **never
///   blocks** (editor findings list + run-start `.summary` channel).
/// - `info`: advisory only, editor-surfaced.
///
/// `Comparable` orders by blocking strength (`info < warning < error`) so
/// callers can fold a findings array to its most-severe tier.
nonisolated public enum LintSeverity: Sendable, Equatable, Comparable {
  case info
  case warning
  case error
}

/// A single semantic-lint finding against a ``Scenario`` (ADR-022).
///
/// Findings are advisory-to-blocking depending on ``severity`` (see
/// ``LintSeverity`` for the three-tier contract). Each carries a stable
/// ``ruleID`` and a fix-hint ``message`` so a blocked scenario is actionable.
nonisolated public struct LintFinding: Sendable, Equatable {
  /// Stable rule identifier (e.g. `"eliminate-needs-vote"`).
  public let ruleID: String

  /// Blocking strength of this finding — see ``LintSeverity``.
  public let severity: LintSeverity

  /// Human-readable description with a fix hint (`String(localized:)` per i18n rules).
  public let message: String

  /// The phase-list index this finding anchors to (editor UI anchor);
  /// `nil` for scenario-level findings.
  public let phaseIndex: Int?

  /// Creates a lint finding.
  ///
  /// - Parameters:
  ///   - ruleID: Stable rule identifier.
  ///   - severity: Blocking strength — see ``LintSeverity``.
  ///   - message: Human-readable description with a fix hint.
  ///   - phaseIndex: Anchoring phase-list index, or `nil` for scenario-level.
  public init(ruleID: String, severity: LintSeverity, message: String, phaseIndex: Int?) {
    self.ruleID = ruleID
    self.severity = severity
    self.message = message
    self.phaseIndex = phaseIndex
  }
}

/// Surfaces silent-no-op / guaranteed-wrong scenario authoring at load time
/// (ADR-022), separate from ``ScenarioValidator``'s fail-fast single-error gate.
///
/// Where ``ScenarioValidator`` throws on the first hard-limit / shape violation,
/// the linter returns a findings array spanning three severity tiers (see
/// ``LintSeverity``): errors block like validation errors, warnings and info
/// never block. It judges *reachability and effect* only — never content
/// quality, thematic fit, or style.
nonisolated public struct ScenarioSemanticLinter: Sendable {

  /// Creates a linter.
  public init() {}

  /// Lints a scenario, returning every finding across all rule groups.
  ///
  /// - Parameter scenario: The scenario to lint.
  /// - Returns: All findings; empty when the scenario is semantically clean.
  public func lint(_ scenario: Scenario) -> [LintFinding] {
    orderingFindings(in: scenario)
      + configFindings(in: scenario)
      + placeholderFindings(in: scenario)
      + conditionFindings(in: scenario)
  }

  // Producer–consumer phase-ordering rules R1–R6 (later moved to a sibling file).
  func orderingFindings(in scenario: Scenario) -> [LintFinding] { [] }

  // Silently-inert configuration rules R7/R8/R9/R17 (later moved to a sibling file).
  func configFindings(in scenario: Scenario) -> [LintFinding] { [] }

  // Placeholder-resolution rules R10–R12 (later moved to a sibling file).
  func placeholderFindings(in scenario: Scenario) -> [LintFinding] { [] }

  // Condition-expression rules R13–R16 (later moved to a sibling file).
  func conditionFindings(in scenario: Scenario) -> [LintFinding] { [] }
}
