import Foundation

/// One agent's score within a ``PastRunListItem`` row preview.
///
/// Only the run's top-scoring agents are projected (highest-first, capped
/// at three) so the Past Results list can render its score chips without
/// retaining the run's full `stateJSON` in memory — see
/// ``SimulationRepository/fetchRecentRunPage(nameQuery:before:limit:)``.
nonisolated public struct PastRunScore: Sendable, Equatable {
  public let name: String
  public let value: Int

  public init(name: String, value: Int) {
    self.name = name
    self.value = value
  }
}

/// A lightweight projection of a `simulations` row for the Past Results list.
///
/// Past Results paginates over potentially thousands of runs, each carrying
/// a heavy `stateJSON` (the full conversation log, ~100-300 KB/run per
/// ADR-015 §2). Materializing whole `SimulationRecord`s would re-create the
/// memory pressure issue #586 set out to fix, so the repository projects each
/// row to this light shape — the columns the list cell renders plus the run's
/// top-3 scores (extracted from `stateJSON` row-by-row and then discarded, so
/// the full state never crosses into app memory).
nonisolated public struct PastRunListItem: Sendable, Equatable, Identifiable {
  public let id: String
  /// Foreign key into `scenarios`. Nil for orphaned runs (the v7
  /// `ON DELETE SET NULL` outcome); such runs label off ``scenarioNameSnapshot``.
  public let scenarioId: String?
  public let createdAt: Date
  /// Raw status string (matches `SimulationStatus.rawValue`); use
  /// ``simulationStatus`` for type-safe access.
  public let status: String
  /// The round the run reached — `K` in the History row's "Round K / N で中断"
  /// summary for a paused run (Home redesign P5 PR2). Projected straight from
  /// `simulations.currentRound`, the same column the Home paused-resume card
  /// reads, so the two surfaces report the same round for one run.
  public let currentRound: Int
  /// Display name captured at run-creation, surfaced for orphaned runs whose
  /// source scenario was deleted.
  public let scenarioNameSnapshot: String?
  /// The source scenario's YAML captured at run-creation (v7+; `nil` for
  /// pre-v7 runs). The History row resolves `agentCount` / total-rounds `N`
  /// from this snapshot in the App layer — snapshot-first, so the row stays
  /// faithful to the scenario that *actually ran* even after a later edit or
  /// deletion (mirrors ``ScenarioSnapshotResolver``). YAML is ~1–5 KB/row —
  /// ~1/100 of the `stateJSON` (~100–300 KB) the projection deliberately drops
  /// (#586), so retaining it over the loaded window stays within that budget.
  public let scenarioYamlSnapshot: String?
  /// The source scenario's gallery category (`GalleryCategory` raw value)
  /// captured at run-creation (v10+; `nil` for pre-v10 runs and runs of local
  /// scenarios). The History row renders its display name via
  /// `GalleryCategory(rawValue:)`. Snapshot-sourced so the row keeps the
  /// category even after the source scenario is edited or deleted (#748).
  public let scenarioCategorySnapshot: String?
  /// The run's highest-scoring agents (highest-first, at most three).
  public let topScores: [PastRunScore]

  public init(
    id: String,
    scenarioId: String?,
    createdAt: Date,
    status: String,
    currentRound: Int,
    scenarioNameSnapshot: String?,
    scenarioYamlSnapshot: String?,
    scenarioCategorySnapshot: String?,
    topScores: [PastRunScore]
  ) {
    self.id = id
    self.scenarioId = scenarioId
    self.createdAt = createdAt
    self.status = status
    self.currentRound = currentRound
    self.scenarioNameSnapshot = scenarioNameSnapshot
    self.scenarioYamlSnapshot = scenarioYamlSnapshot
    self.scenarioCategorySnapshot = scenarioCategorySnapshot
    self.topScores = topScores
  }

  /// Type-safe accessor for the run status.
  public var simulationStatus: SimulationStatus? {
    SimulationStatus(rawValue: status)
  }
}

/// Keyset (seek) cursor for ``SimulationRepository/fetchRecentRunPage(nameQuery:before:limit:)``.
///
/// Pagination is keyset rather than `LIMIT/OFFSET` so a run inserted at the
/// top of the recency stream (e.g. a background simulation completing
/// mid-scroll, ADR-003) cannot shift the window and duplicate/skip rows. The
/// cursor is the previous page's **last raw row**; the next page selects rows
/// strictly older than it on the composite `(createdAt DESC, id DESC)` order.
nonisolated public struct SimulationPageCursor: Sendable, Equatable {
  public let createdAt: Date
  public let id: String

  public init(createdAt: Date, id: String) {
    self.createdAt = createdAt
    self.id = id
  }
}
