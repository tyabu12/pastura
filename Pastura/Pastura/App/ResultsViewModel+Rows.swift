import Foundation

// The Past Results list's value types — extracted from `ResultsViewModel` to
// keep that file within SwiftLint's file/type-body length budgets. Pure data
// holders; they touch no ViewModel instance state.
extension ResultsViewModel {

  /// One simulation row within a ``ResultSection``.
  ///
  /// `variantName` is the simulation-time variant's display name — the
  /// `ScenarioRecord.name` of the variant whose `id` matches the run's
  /// `scenarioId` (or the captured snapshot for a deleted scenario). Kept
  /// un-translated (per-variant) so the label stays consistent with the run's
  /// recorded conversation content.
  struct SimulationRow: Identifiable, Sendable {
    let item: PastRunListItem
    let variantName: String
    /// Agent count resolved from the run's scenario definition (snapshot-first,
    /// see ``RunScenarioMetaResolver``). `nil` when the YAML is missing or failed
    /// to parse — the row then draws no sheep avatars. Carries the *resolved
    /// data*, not the formatted summary, so the View owns all display formatting
    /// via ``ResultsRowFormat`` (App keeps no Views dependency).
    let agentCount: Int?
    /// Total rounds `N` from the scenario definition — `N` in the row's
    /// "All N rounds complete" / "Paused at Round K / N" summary. `nil` when
    /// unknown, which routes the summary to its bare "Complete" / "Paused at
    /// Round K" form.
    let totalRounds: Int?
    var id: String { item.id }
  }

  /// One section in the results list.
  ///
  /// For the aggregate path `title` is the date-bucket heading (Today / This
  /// Week / …) and `key` is the bucket's stable identity
  /// (``ResultsRowFormat/DateBucket/key``). For the detail path it is the
  /// single scenario's `name` / canonical id. `key` is kept separate from the
  /// display `title` so sections coalesce by identity across keyset pages.
  struct ResultSection: Identifiable, Sendable {
    let key: String
    let title: String
    let rows: [SimulationRow]
    var id: String { key }
  }
}
