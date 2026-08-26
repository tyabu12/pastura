import Foundation

// Install-state projection of `SharedScenariosViewModel`, split out of the
// main file for the SwiftLint `file_length` budget (#1565). Stored state
// (`installedBySourceId`, `sessionPinnedIds`) stays in the main file —
// extensions cannot add stored properties — and everything here is derived
// from it synchronously so views can read it without a hop.
extension SharedScenariosViewModel {

  // MARK: - Install-state filter

  /// Gallery ids installed locally whose local hash equals the gallery hash
  /// (installed AND no update available), minus ``sessionPinnedIds``. Feeds
  /// the sort-last key in ``GalleryScenarioSearch`` — installed-and-unchanged
  /// rows still show in Browse, just at the bottom.
  var installedUnchangedIds: Set<String> {
    installedUnchangedIds(in: allScenarios, snapshot: installedBySourceId)
      .subtracting(sessionPinnedIds)
  }

  // MARK: - Sync helpers for UI

  /// True if a gallery row for this scenario is already in the local DB.
  func isInstalled(_ scenario: GalleryScenario) -> Bool {
    installedBySourceId[scenario.id] != nil
  }

  /// True if an installed gallery row's `sourceHash` differs from the
  /// current gallery's `yaml_sha256`.
  func hasUpdate(for scenario: GalleryScenario) -> Bool {
    guard let local = installedBySourceId[scenario.id] else { return false }
    return local.sourceHash != scenario.yamlSHA256
  }

  /// Whether this build's engine can execute `scenario` (ADR-020 D2 + D3).
  ///
  /// Drives the Browse-tab grey-out: an incompatible entry renders as a
  /// dimmed, non-tappable card with an "update app" badge instead of a
  /// `NavigationLink` (see ``SharedScenariosListView``). Delegates to
  /// ``EngineSchemaVersion`` so the capability comparison stays in the Engine
  /// layer and drift-proof against `PhaseType` additions.
  func isCompatible(_ scenario: GalleryScenario) -> Bool {
    EngineSchemaVersion.isCompatible(
      phases: scenario.phases, minEngineVersion: scenario.minEngineVersion)
  }

  /// Ids in `scenarios` that `snapshot` holds with a matching hash — the
  /// raw "installed and unchanged" set before session pins are subtracted.
  /// Internal (not `private`) because the main file's
  /// ``refreshInstalledSnapshot()`` diffs two snapshots through it.
  func installedUnchangedIds(
    in scenarios: [GalleryScenario], snapshot: [String: ScenarioRecord]
  ) -> Set<String> {
    Set(
      scenarios.compactMap { scenario in
        guard let local = snapshot[scenario.id], local.sourceHash == scenario.yamlSHA256
        else { return nil }
        return scenario.id
      })
  }
}
