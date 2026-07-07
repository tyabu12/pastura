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

  /// Cross-language sibling variant per ADR-010 D4 — a different
  /// `ScenarioRecord.id` that shares this scenario's canonical
  /// `sourceId`. `nil` when no sibling exists (the user-authored
  /// scenarios path) or when the current record's `sourceId` is `nil`
  /// (Phase 1 / pre-Step-D legacy install without the install-time
  /// `sourceId` wiring — D11 row 351 install-base reset territory).
  ///
  /// Populated by ``loadSibling()`` after ``load(scenarioId:)``
  /// completes; the View renders a "View in [other language]"
  /// affordance when non-nil.
  private(set) var siblingVariant: ScenarioRecord?

  /// Whether the scenario can be launched (valid + within limits).
  var canRun: Bool { scenario != nil && validationError == nil }

  /// True for records imported from the gallery — read-only locally.
  var isGallerySourced: Bool {
    record?.sourceType == ScenarioSourceType.gallery
  }

  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()
  private let validator = ScenarioValidator()
  /// Semantic linter (ADR-022). Its `.error` findings gate `canRun` on the
  /// same `validationError` surface as structural validation; warnings/info
  /// are not displayed here (PR2 editor-UX scope).
  private let linter = ScenarioSemanticLinter()

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
        errorMessage = String(localized: "Scenario not found")
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
        // Semantic-lint errors gate `canRun` like structural errors (ADR-022).
        let lintErrors = linter.lint(parsed).filter { $0.severity == .error }
        if !lintErrors.isEmpty {
          validationError = lintErrors.map(\.message).joined(separator: "\n")
        }
      } catch {
        validationError = error.localizedDescription
      }
    } catch {
      errorMessage = String(
        format: String(localized: "Failed to load scenario: %@"), error.localizedDescription
      )
    }

    isLoading = false
  }

  /// Populates `galleryScenario` and `hasGalleryUpdate` by matching the
  /// current record's `sourceId` against the cached gallery index. Silent
  /// no-op for non-gallery records or when no cache exists.
  func refreshGalleryStatus(using service: any GalleryService) async {
    guard
      let record,
      record.sourceType == ScenarioSourceType.gallery,
      let sourceId = record.sourceId
    else {
      galleryScenario = nil
      hasGalleryUpdate = false
      return
    }
    // Cache read is file I/O — dispatch off MainActor. Double-optional:
    // inner nil = no cache file, outer nil = offMain threw.
    let fetched = try? await offMain { [service] in try service.loadCachedIndex() }
    guard
      let cached = fetched.flatMap({ $0 }),
      let entry = cached.scenarios.first(where: { $0.id == sourceId })
    else {
      galleryScenario = nil
      hasGalleryUpdate = false
      return
    }
    galleryScenario = entry
    hasGalleryUpdate = record.sourceHash != entry.yamlSHA256
  }

  /// Populates ``siblingVariant`` by searching the repository for a
  /// different record sharing the loaded record's canonical
  /// `sourceId`. Silent no-op when no current record is loaded or its
  /// `sourceId` is `nil` — both paths produce `siblingVariant == nil`,
  /// which the View renders as "no language-switch affordance".
  ///
  /// Step D ships ja↔en sibling pairs for the 4 bundled presets via
  /// ``PresetLoader/canonicalSourceId(for:)`` (#388 Item 3). Gallery-
  /// imported scenarios don't currently ship language siblings; if a
  /// future curation flow produces them they automatically participate
  /// in this resolver via the same `sourceId` column (ADR-010 D4
  /// "cross-language alias" semantics).
  func loadSibling() async {
    guard
      let record,
      let sourceId = record.sourceId
    else {
      siblingVariant = nil
      return
    }

    // Repository fetch off MainActor. Resolve the sibling via the
    // lightweight ``ScenarioSummary`` projection (only `id` + `sourceId`
    // are needed to match), then load that single record's full row —
    // avoids pulling every scenario's heavy `yamlDefinition` into memory
    // for a one-row lookup (#704). `fetchAllSummaries()` returns rows
    // newest-first (`createdAt DESC`), so `.first` preserves the
    // newest-wins tie-break when multiple records share the canonical
    // `sourceId`.
    let summaries = try? await offMain { [repository] in
      try repository.fetchAllSummaries()
    }
    guard
      let siblingId = summaries?.first(where: { summary in
        summary.id != record.id && summary.sourceId == sourceId
      })?.id
    else {
      siblingVariant = nil
      return
    }
    siblingVariant = try? await offMain { [repository] in
      try repository.fetchById(siblingId)
    }
  }

  func deleteScenario() async -> Bool {
    guard let id = record?.id else { return false }
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      return true
    } catch {
      errorMessage = String(
        format: String(localized: "Failed to delete: %@"), error.localizedDescription)
      return false
    }
  }
}
