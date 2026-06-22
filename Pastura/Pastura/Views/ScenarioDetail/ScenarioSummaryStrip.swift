import Foundation

/// Pure formatting for the scenario-detail hero summary strip shown under
/// the title — e.g. `Agents 2 · Rounds 1 · Est. Inferences 2`.
///
/// Marked `nonisolated` at the type level so the formatter is unit-testable
/// without constructing a View or hopping to the main actor (avoids the
/// default-MainActor conformance-lookup trap — see
/// `.claude/rules/swift-isolation.md`).
///
/// Named `…Strip` to stay distinct from the unrelated Data-layer
/// `ScenarioSummary` record type (a same-base-name file would also collide
/// on `*.stringsdata` at build time).
nonisolated enum ScenarioSummaryStrip {
  /// Joins `label value` stat fragments with a middle-dot separator —
  /// e.g. `[("Agents", 2), ("Rounds", 1)]` → `Agents 2 · Rounds 1`.
  ///
  /// Labels are passed in **already localized** by the caller (Form-B i18n
  /// boundary): the View resolves `String(localized: "Agents")` etc., so no
  /// English literal becomes a runtime catalog-lookup key and the existing
  /// translated keys are reused verbatim (no new catalog keys, no plural
  /// variations). The numeric values are display-only interpolation, never
  /// a lookup key.
  static func text(stats: [(label: String, value: Int)]) -> String {
    stats.map { "\($0.label) \($0.value)" }.joined(separator: " · ")
  }
}
