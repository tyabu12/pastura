import Foundation
import GRDB

/// A lightweight projection of a `scenarios` row that excludes the heavy
/// `yamlDefinition` column.
///
/// Home and Past Results derive cross-language variant grouping (ADR-010
/// D4/D6 — collapse by `sourceId`, surface the device-language variant) and
/// per-row display labels from a small set of columns. Materializing whole
/// `ScenarioRecord`s would load every row's full YAML into memory just to read
/// `name` / `sourceId` / `language` — the residual unbounded load flagged in
/// #586 / PR #674. This projection carries only those columns; the
/// denormalized ``language`` (ADR-010 D1) lets the collapse pick the
/// device-language variant without parsing YAML.
///
/// Mirrors ``PastRunListItem`` (the `stateJSON`-excluding run projection).
nonisolated public struct ScenarioSummary: Sendable, Equatable, Identifiable,
  Decodable, FetchableRecord {
  public let id: String
  public let name: String
  public let isPreset: Bool
  /// Canonical cross-language link (ADR-010 D4). Variants of the same scenario
  /// share a `sourceId`; legacy rows group by `id` (`sourceId == nil`).
  public let sourceId: String?
  /// Denormalized ISO 639-1 language code (`"ja"` / `"en"`). `nil` for rows
  /// written before the v8 column (not backfilled — consumers fall back to
  /// `"ja"`, matching ``ScenarioYAMLLanguage``).
  public let language: String?

  public init(id: String, name: String, isPreset: Bool, sourceId: String?, language: String?) {
    self.id = id
    self.name = name
    self.isPreset = isPreset
    self.sourceId = sourceId
    self.language = language
  }
}
