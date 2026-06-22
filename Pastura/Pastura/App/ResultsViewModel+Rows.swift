import Foundation

// The Past Results list's value types — extracted from `ResultsViewModel` to
// keep that file within SwiftLint's file/type-body length budgets. Pure data
// holders; they touch no ViewModel instance state.
extension ResultsViewModel {

  /// One simulation row within a ``ResultSection``.
  ///
  /// `variantName` is the simulation-time variant's display name — the
  /// `ScenarioSummary.name` of the variant whose `id` matches the run's
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
    /// The scenario's 1-line description from its definition (snapshot-first,
    /// see ``RunScenarioMetaResolver``). `nil` when the YAML is missing, failed
    /// to parse, or the description is empty / whitespace-only — the row then
    /// draws no description line (graceful degrade, #747).
    let description: String?
    /// The run's snapshot gallery category (`GalleryCategory` raw value), from
    /// ``PastRunListItem/scenarioCategorySnapshot`` (#748). `nil` for runs of
    /// local scenarios and pre-v10 runs. The View resolves its display name via
    /// ``ResultsRowFormat/categoryCaption(for:)`` — the row carries the raw
    /// resolved data, not the formatted caption (App keeps no Views dependency).
    let category: String?
    var id: String { item.id }
  }

  /// Builds a ``SimulationRow`` from a run and its resolved scenario meta —
  /// shared by the aggregate (`rebuildSections`) and detail
  /// (`loadDetailPerVariant`) paths so the carrier's field list lives in one
  /// place. Pure mapping; touches no ViewModel state.
  func makeRow(
    _ item: PastRunListItem, meta: RunScenarioMetaResolver.Meta, variantName: String
  ) -> SimulationRow {
    SimulationRow(
      item: item, variantName: variantName,
      agentCount: meta.agentCount, totalRounds: meta.rounds,
      description: meta.description, category: item.scenarioCategorySnapshot)
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
