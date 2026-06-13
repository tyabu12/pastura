import Foundation

/// Resolves the `ScenarioRecord` to use when displaying or exporting a past
/// simulation run.
///
/// Past results must be faithful to the scenario that *actually ran*, not to
/// the live scenario row — which the user may have since edited or deleted.
/// Since the v7 migration, each run carries a `scenarioYamlSnapshot` +
/// `scenarioNameSnapshot` captured at creation time. This resolver:
///
/// 1. **Prefers the snapshot** when present — fixing edit-drift (a later edit
///    to the live scenario no longer changes historical runs) and surviving
///    deletion (orphaned runs whose `scenarioId` is `nil` still resolve).
/// 2. **Falls back to the live scenario** for pre-v7 runs that predate the
///    snapshot columns; those still carry a valid `scenarioId`.
/// 3. Returns `nil` only when neither source is available.
///
/// The synthesized record is a transient value (never persisted), so read
/// paths that consume a non-optional `ScenarioRecord`
/// (`ResultDetailExportAssembler`, `ResultMarkdownExporter.Input`) keep their
/// signatures unchanged.
nonisolated enum ScenarioSnapshotResolver {
  /// - Parameters:
  ///   - simulation: The run whose scenario should be resolved.
  ///   - liveLookup: Fetches the live `ScenarioRecord` by id (typically
  ///     `ScenarioRepository.fetchById`). Only invoked for pre-v7 runs with
  ///     no snapshot.
  static func resolve(
    for simulation: SimulationRecord,
    liveLookup: (String) throws -> ScenarioRecord?
  ) rethrows -> ScenarioRecord? {
    if let snapshotYaml = simulation.scenarioYamlSnapshot {
      return ScenarioRecord(
        id: simulation.scenarioId ?? simulation.id,
        name: simulation.scenarioNameSnapshot ?? "",
        yamlDefinition: snapshotYaml,
        isPreset: false,
        createdAt: simulation.createdAt,
        updatedAt: simulation.updatedAt)
    }
    guard let scenarioId = simulation.scenarioId else { return nil }
    return try liveLookup(scenarioId)
  }
}
