import Foundation

/// ViewModel for the Shared Scenarios screen.
///
/// Orchestrates offline-first loading of the gallery index, category
/// filtering, and the "Try" / "Update" install flow. Keeps a snapshot of
/// locally-installed gallery rows so update-available badges and
/// installation-status checks can be rendered synchronously from views.
@Observable
@MainActor
final class SharedScenariosViewModel {

  /// The top-level screen state the view renders.
  enum LoadState: Equatable, Sendable {
    /// No attempt yet.
    case idle
    /// First load, no cache — network in flight.
    case loading
    /// At least one index is available (from cache or fresh fetch).
    case loaded
    /// Network failed but cached content is available.
    case offlineWithCache
    /// First run with no cache and no network.
    case empty
  }

  /// The result of a `tryInstall` invocation.
  enum TryOutcome: Equatable, Sendable {
    /// Scenario saved as a fresh install.
    case installed(scenarioId: String)
    /// Scenario already existed as a gallery row; its YAML was updated in place.
    case updated(scenarioId: String)
    /// Primary-key collision with a non-gallery local row — cannot install.
    /// Includes the existing row's display name so the user can locate it.
    case conflict(existingName: String, existingId: String)
    /// Network failed or YAML could not be parsed.
    case networkError(String)
    /// Downloaded YAML did not match the `yaml_sha256` from the gallery index.
    case hashMismatch
  }

  private(set) var state: LoadState = .idle
  private(set) var allScenarios: [GalleryScenario] = []
  private(set) var updatedAt: String?

  /// `nil` means "all categories".
  var selectedCategory: GalleryCategory?

  /// The Browse-tab search field text. Blank / whitespace-only applies no
  /// text filter (see ``GalleryScenarioSearch/filter(_:category:query:)``).
  var searchQuery: String = ""

  /// Rows keyed by `sourceId` for the subset of scenarios whose
  /// `sourceType == "gallery"` and whose `sourceId` is non-nil. Rebuilt
  /// after every load and save so UI bindings can read synchronously.
  private(set) var installedBySourceId: [String: ScenarioRecord] = [:]

  /// Filtered view based on `selectedCategory` AND `searchQuery`. The actual
  /// filtering lives in the pure ``GalleryScenarioSearch`` so it is
  /// unit-testable without the ViewModel (ADR-009).
  var visibleScenarios: [GalleryScenario] {
    GalleryScenarioSearch.filter(
      allScenarios, category: selectedCategory, query: searchQuery,
      language: nil)
  }

  /// Why ``visibleScenarios`` is empty — drives the empty-card copy. Only
  /// meaningful when ``visibleScenarios`` is actually empty.
  var emptyReason: GalleryScenarioSearch.EmptyReason {
    GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: allScenarios.isEmpty,
      category: selectedCategory, query: searchQuery, language: nil)
  }

  private let galleryService: any GalleryService
  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()

  init(galleryService: any GalleryService, repository: any ScenarioRepository) {
    self.galleryService = galleryService
    self.repository = repository
  }

  // MARK: - Loading

  /// Offline-first entry point. Shows cached content immediately (if any),
  /// then kicks off a network refresh.
  func load() async {
    await refreshInstalledSnapshot()

    if let cached = try? galleryService.loadCachedIndex() {
      apply(index: cached)
      state = .loaded
    } else {
      state = .loading
    }

    await refresh()
  }

  /// Force a network refresh. Preserves cached content on failure.
  func refresh() async {
    do {
      if let fresh = try await galleryService.refreshIndex() {
        apply(index: fresh)
        state = .loaded
      } else if allScenarios.isEmpty {
        // 304 with no prior cache shouldn't happen (no ETag), but stay safe.
        state = .empty
      } else {
        state = .loaded
      }
    } catch {
      if allScenarios.isEmpty {
        state = .empty
      } else {
        state = .offlineWithCache
      }
    }
  }

  // MARK: - Install flow

  /// Attempts to install or update `scenario`. See `TryOutcome` for the
  /// five possible results.
  func tryInstall(_ scenario: GalleryScenario) async -> TryOutcome {
    let existing: ScenarioRecord?
    switch await resolveExisting(scenario) {
    case .conflict(let outcome): return outcome
    case .fresh: existing = nil
    case .sameGalleryRow(let row): existing = row
    }

    let yaml: String
    do {
      yaml = try await galleryService.fetchScenarioYAML(
        from: scenario.yamlURL, expectedSHA256: scenario.yamlSHA256)
    } catch let error as GalleryServiceError {
      if case .hashMismatch = error { return .hashMismatch }
      return .networkError(error.localizedDescription)
    } catch {
      return .networkError(error.localizedDescription)
    }

    // Parse to validate structure and pull the display name. The parsed
    // Scenario.id must match the gallery scenario id so the codebase-wide
    // invariant (record.id == parsed.id) holds — enforced by the curation
    // rule that gallery ids don't collide with preset ids.
    let parsed: Scenario
    do {
      parsed = try loader.load(yaml: yaml)
    } catch {
      return .networkError(
        String(
          format: String(localized: "Failed to parse gallery YAML: %@"),
          error.localizedDescription))
    }

    do {
      try await saveGalleryRecord(
        parsed: parsed, yaml: yaml, scenario: scenario, existing: existing)
    } catch {
      return .networkError(
        String(format: String(localized: "Save failed: %@"), error.localizedDescription))
    }

    await refreshInstalledSnapshot()
    return existing == nil
      ? .installed(scenarioId: parsed.id)
      : .updated(scenarioId: parsed.id)
  }

  /// Classifies the local state for a gallery id without fetching YAML.
  private enum ExistingCheck {
    case fresh
    case sameGalleryRow(ScenarioRecord)
    case conflict(TryOutcome)
  }

  private func resolveExisting(_ scenario: GalleryScenario) async -> ExistingCheck {
    let existing: ScenarioRecord?
    do {
      existing = try await offMain { [repository] in
        try repository.fetchById(scenario.id)
      }
    } catch {
      return .conflict(
        .networkError(
          String(
            format: String(localized: "Could not check local scenarios: %@"),
            error.localizedDescription)))
    }
    guard let existing else { return .fresh }
    let isSameGalleryRow =
      existing.sourceType == ScenarioSourceType.gallery
      && existing.sourceId == scenario.id
    if isSameGalleryRow {
      return .sameGalleryRow(existing)
    }
    return .conflict(.conflict(existingName: existing.name, existingId: existing.id))
  }

  private func saveGalleryRecord(
    parsed: Scenario,
    yaml: String,
    scenario: GalleryScenario,
    existing: ScenarioRecord?
  ) async throws {
    let record = ScenarioRecord(
      id: parsed.id,
      name: parsed.name,
      yamlDefinition: yaml,
      isPreset: false,
      createdAt: existing?.createdAt ?? Date(),
      updatedAt: Date(),
      sourceType: ScenarioSourceType.gallery,
      sourceId: scenario.id,
      sourceHash: scenario.yamlSHA256,
      language: parsed.language,
      // Denormalize the gallery category so Home / Past Results can surface it
      // without the live gallery feed (#748). Raw value; the enum is not in Data.
      category: scenario.category.rawValue
    )
    try await offMain { [repository] in
      try repository.save(record)
    }
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

  // MARK: - Private

  private func apply(index: GalleryIndex) {
    allScenarios = index.scenarios
    updatedAt = index.updatedAt
  }

  private func refreshInstalledSnapshot() async {
    let rows: [ScenarioRecord]
    do {
      rows = try await offMain { [repository] in
        try repository.fetchBySourceType(ScenarioSourceType.gallery)
      }
    } catch {
      // Soft-fail: keep stale snapshot rather than clearing UI state on a
      // transient DB error.
      return
    }
    // Use `uniquingKeysWith` rather than `uniqueKeysWithValues` to avoid
    // trapping if two gallery rows ever share a `sourceId` (shouldn't
    // happen under the curation rules + readonly guard, but we prefer
    // "first wins" over a crash).
    installedBySourceId = Dictionary(
      rows.compactMap { record -> (String, ScenarioRecord)? in
        guard let sourceId = record.sourceId else { return nil }
        return (sourceId, record)
      },
      uniquingKeysWith: { first, _ in first })
  }
}
