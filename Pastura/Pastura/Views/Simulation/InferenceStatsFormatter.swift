import Foundation

/// Formats the inference-stats label rendered in the simulation
/// header (e.g. `"12.4 tok/s • 1.8s"`).
///
/// Pure helper extracted from `SimulationView` so the nil-empty
/// branch can be unit-tested without instantiating the view per
/// ADR-009. Returns `nil` when both inputs are nil so callers can
/// short-circuit and render nothing instead of an all-dash string.
nonisolated enum InferenceStatsFormatter {

  /// Returns a `"<tps> tok/s • <duration>s"` string when at least
  /// one input is non-nil; nil otherwise. Individually-nil inputs
  /// render as `—`, matching the original inline formatter.
  static func format(durationSeconds: Double?, tokensPerSecond: Double?) -> String? {
    guard durationSeconds != nil || tokensPerSecond != nil else { return nil }
    let tpsPart = tokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "— tok/s"
    let durationPart = durationSeconds.map { String(format: "%.1fs", $0) } ?? "—"
    return "\(tpsPart) • \(durationPart)"
  }
}
