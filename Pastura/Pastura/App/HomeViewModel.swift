import Foundation

/// ViewModel for the home screen scenario list.
///
/// Fetches scenarios from the repository and splits them into presets
/// and user-created groups. Supports pull-to-refresh and deletion.
/// Also exposes a set of scenario ids with a pending gallery update,
/// populated from the cached gallery index.
@Observable
final class HomeViewModel {
  private(set) var presets: [ScenarioRecord] = []
  private(set) var userScenarios: [ScenarioRecord] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  /// `ScenarioRecord.id`s for rows whose `sourceHash` differs from the
  /// cached gallery's `yaml_sha256`. Empty when no cache exists. The view
  /// reads this as an inline badge on each row.
  private(set) var galleryUpdateBadges: Set<String> = []

  private let repository: any ScenarioRepository

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  func loadScenarios() async {
    isLoading = true
    errorMessage = nil

    do {
      let all = try await offMain { [repository] in
        try repository.fetchAll()
      }
      presets = all.filter(\.isPreset)
      userScenarios = all.filter { !$0.isPreset }
    } catch {
      errorMessage = "Failed to load scenarios: \(error.localizedDescription)"
    }

    isLoading = false
  }

  func deleteScenario(_ id: String) async {
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      userScenarios.removeAll { $0.id == id }
    } catch {
      errorMessage = "Failed to delete scenario: \(error.localizedDescription)"
    }
  }

  /// Recomputes `galleryUpdateBadges` by comparing each locally-stored
  /// gallery row's `sourceHash` with the hash from the cached gallery
  /// index. Non-gallery rows and rows lacking a `sourceId` are ignored.
  /// Silent no-op when no cached index is available.
  func refreshGalleryUpdateBadges(using service: any GalleryService) async {
    let cached: GalleryIndex?
    do {
      cached = try service.loadCachedIndex()
    } catch {
      cached = nil
    }
    guard let cached else {
      galleryUpdateBadges = []
      return
    }
    let hashBySourceId = Dictionary(
      uniqueKeysWithValues: cached.scenarios.map { ($0.id, $0.yamlSHA256) })
    var ids: Set<String> = []
    for record in presets + userScenarios
    where record.sourceType == ScenarioSourceType.gallery {
      guard
        let sourceId = record.sourceId,
        let galleryHash = hashBySourceId[sourceId]
      else { continue }
      if record.sourceHash != galleryHash {
        ids.insert(record.id)
      }
    }
    galleryUpdateBadges = ids
  }
}
