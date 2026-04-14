import Foundation

/// ViewModel for the scenario detail screen.
///
/// Parses the YAML definition into a `Scenario` for rich display,
/// validates before launch, and estimates inference count.
@Observable
final class ScenarioDetailViewModel {
  private(set) var record: ScenarioRecord?
  private(set) var scenario: Scenario?
  private(set) var estimatedInferences: Int = 0
  private(set) var validationError: String?
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  /// Gallery entry matching this scenario's `sourceId`, loaded from the
  /// cached gallery index. `nil` unless the local record is gallery-sourced
  /// and the cached index contains a matching entry.
  private(set) var galleryScenario: GalleryScenario?

  /// True when `record.sourceHash` differs from `galleryScenario?.yamlSHA256`.
  private(set) var hasGalleryUpdate = false

  /// Whether the scenario can be launched (valid + within limits).
  var canRun: Bool { scenario != nil && validationError == nil }

  /// True for records imported from the gallery — read-only locally.
  var isGallerySourced: Bool {
    record?.sourceType == ScenarioSourceType.gallery
  }

  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()
  private let validator = ScenarioValidator()

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  func load(scenarioId: String) async {
    isLoading = true
    errorMessage = nil
    validationError = nil

    do {
      guard
        let fetched = try await offMain({ [repository] in
          try repository.fetchById(scenarioId)
        })
      else {
        errorMessage = "Scenario not found"
        isLoading = false
        return
      }

      record = fetched
      let parsed = try loader.load(yaml: fetched.yamlDefinition)
      scenario = parsed
      estimatedInferences = ScenarioLoader.estimateInferenceCount(parsed)

      // Validate
      do {
        _ = try validator.validate(parsed)
      } catch {
        validationError = error.localizedDescription
      }
    } catch {
      errorMessage = "Failed to load scenario: \(error.localizedDescription)"
    }

    isLoading = false
  }

  /// Populates `galleryScenario` and `hasGalleryUpdate` by matching the
  /// current record's `sourceId` against the cached gallery index. Silent
  /// no-op for non-gallery records or when no cache exists.
  func refreshGalleryStatus(using service: any GalleryService) {
    guard
      let record,
      record.sourceType == ScenarioSourceType.gallery,
      let sourceId = record.sourceId
    else {
      galleryScenario = nil
      hasGalleryUpdate = false
      return
    }
    let cached = try? service.loadCachedIndex()
    guard let entry = cached?.scenarios.first(where: { $0.id == sourceId }) else {
      galleryScenario = nil
      hasGalleryUpdate = false
      return
    }
    galleryScenario = entry
    hasGalleryUpdate = record.sourceHash != entry.yamlSHA256
  }

  func deleteScenario() async -> Bool {
    guard let id = record?.id else { return false }
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      return true
    } catch {
      errorMessage = "Failed to delete: \(error.localizedDescription)"
      return false
    }
  }
}
