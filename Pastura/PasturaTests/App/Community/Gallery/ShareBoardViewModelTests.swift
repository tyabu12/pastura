import CryptoKit
import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct ShareBoardViewModelTests {

  // MARK: - Fixtures

  private func makeRepo() throws -> GRDBScenarioRepository {
    let manager = try DatabaseManager.inMemory()
    return GRDBScenarioRepository(dbWriter: manager.dbWriter)
  }

  private static let sampleYAML = """
    id: asch_v1
    name: Asch Conformity
    description: Conformity under social pressure
    agents: 3
    rounds: 1
    context: Three participants see line lengths
    personas:
      - name: Alice
        description: Confident
      - name: Bob
        description: Anxious
      - name: Charlie
        description: Neutral
    phases:
      - type: speak_all
        prompt: "State your opinion"
        output:
          statement: string
    """

  private static var sampleYAMLHash: String {
    // swiftlint:disable:next force_unwrapping
    URLSessionGalleryService.sha256Hex(sampleYAML.data(using: .utf8)!)
  }

  private func makeGalleryScenario(
    id: String = "asch_v1",
    hash: String? = nil
  ) -> GalleryScenario {
    GalleryScenario(
      id: id,
      title: "Asch",
      category: .socialPsychology,
      description: "desc",
      author: "t",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 10,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/\(id).yaml")!,
      yamlSHA256: hash ?? Self.sampleYAMLHash,
      addedAt: "2026-04-14")
  }

  private func makeIndex(_ scenarios: [GalleryScenario]) -> GalleryIndex {
    GalleryIndex(version: 1, updatedAt: "2026-04-14T00:00:00Z", scenarios: scenarios)
  }

  // MARK: - load / offline-first

  @Test func loadShowsCachedIndexBeforeNetwork() async throws {
    let repo = try makeRepo()
    let cachedIndex = makeIndex([makeGalleryScenario()])
    let service = MockGalleryService()
    service.cachedIndex = cachedIndex
    service.refreshResult = .success(nil)  // 304 unchanged

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.state == .loaded)
    #expect(viewModel.allScenarios.count == 1)
  }

  @Test func loadFallsBackToEmptyWhenNoCacheAndNetworkFails() async throws {
    let repo = try makeRepo()
    let service = MockGalleryService()
    service.cachedIndex = nil
    service.refreshResult = .failure(GalleryServiceError.invalidResponse)

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.state == .empty)
    #expect(viewModel.allScenarios.isEmpty)
  }

  @Test func loadUsesOfflineStateWhenNetworkFailsAfterCacheLoaded() async throws {
    let repo = try makeRepo()
    let service = MockGalleryService()
    service.cachedIndex = makeIndex([makeGalleryScenario()])
    service.refreshResult = .failure(GalleryServiceError.invalidResponse)

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.state == .offlineWithCache)
    #expect(viewModel.allScenarios.count == 1)
  }

  @Test func refreshAppliesFreshIndex() async throws {
    let repo = try makeRepo()
    let service = MockGalleryService()
    service.cachedIndex = nil
    service.refreshResult = .success(makeIndex([makeGalleryScenario()]))

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.state == .loaded)
    #expect(viewModel.allScenarios.count == 1)
  }

  // MARK: - category filter

  @Test func visibleScenariosFilterByCategory() async throws {
    let repo = try makeRepo()
    let service = MockGalleryService()
    let first = makeGalleryScenario(id: "a")
    var second = makeGalleryScenario(id: "b")
    second = GalleryScenario(
      id: second.id, title: second.title, category: .ethics,
      description: second.description, author: second.author,
      recommendedModel: second.recommendedModel,
      estimatedInferences: second.estimatedInferences, yamlURL: second.yamlURL,
      yamlSHA256: second.yamlSHA256, addedAt: second.addedAt)
    service.cachedIndex = makeIndex([first, second])
    service.refreshResult = .success(nil)

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    await viewModel.load()
    #expect(viewModel.visibleScenarios.count == 2)

    viewModel.selectedCategory = .socialPsychology
    #expect(viewModel.visibleScenarios.map(\.id) == ["a"])

    viewModel.selectedCategory = .ethics
    #expect(viewModel.visibleScenarios.map(\.id) == ["b"])

    viewModel.selectedCategory = nil
    #expect(viewModel.visibleScenarios.count == 2)
  }

  // MARK: - tryInstall

  @Test func tryInstallFreshReturnsInstalledAndSavesGalleryRecord() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario()
    let service = MockGalleryService()
    service.yamlFor = [scenario.yamlURL: Self.sampleYAML]

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    let outcome = await viewModel.tryInstall(scenario)

    #expect(outcome == .installed(scenarioId: "asch_v1"))
    let saved = try repo.fetchById("asch_v1")
    #expect(saved?.sourceType == ScenarioSourceType.gallery)
    #expect(saved?.sourceId == "asch_v1")
    #expect(saved?.sourceHash == Self.sampleYAMLHash)
  }

  @Test func tryInstallConflictsWithLocalNonGalleryRow() async throws {
    let repo = try makeRepo()
    // Seed a local scenario with the same id but no source tag.
    try repo.save(
      ScenarioRecord(
        id: "asch_v1", name: "My Local Version",
        yamlDefinition: "yaml: local",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let scenario = makeGalleryScenario()
    let service = MockGalleryService()
    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)

    let outcome = await viewModel.tryInstall(scenario)
    #expect(outcome == .conflict(existingName: "My Local Version", existingId: "asch_v1"))
  }

  @Test func tryInstallSameGalleryRowReturnsUpdated() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario()
    let service = MockGalleryService()
    service.yamlFor = [scenario.yamlURL: Self.sampleYAML]

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    _ = await viewModel.tryInstall(scenario)  // install

    // Bump hash → update path
    let updated = makeGalleryScenario(hash: Self.sampleYAMLHash)
    let outcome = await viewModel.tryInstall(updated)
    #expect(outcome == .updated(scenarioId: "asch_v1"))
  }

  @Test func tryInstallReportsHashMismatch() async throws {
    let repo = try makeRepo()
    // Claim a wrong hash in the gallery entry.
    let scenario = makeGalleryScenario(hash: String(repeating: "0", count: 64))
    let service = MockGalleryService()
    service.yamlFor = [scenario.yamlURL: Self.sampleYAML]
    service.mismatchMode = .rejectHash

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    let outcome = await viewModel.tryInstall(scenario)
    #expect(outcome == .hashMismatch)

    // Nothing saved
    #expect(try repo.fetchById("asch_v1") == nil)
  }

  @Test func tryInstallReportsNetworkError() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario()
    let service = MockGalleryService()
    service.yamlErrorFor = [scenario.yamlURL: GalleryServiceError.unexpectedStatus(500)]

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)
    let outcome = await viewModel.tryInstall(scenario)

    if case .networkError = outcome {
      // expected
    } else {
      Issue.record("Expected .networkError, got \(outcome)")
    }
    #expect(try repo.fetchById("asch_v1") == nil)
  }

  // MARK: - isInstalled / hasUpdate

  @Test func installedAndUpdateFlagsReflectLocalState() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario()
    let service = MockGalleryService()
    service.yamlFor = [scenario.yamlURL: Self.sampleYAML]

    let viewModel = ShareBoardViewModel(galleryService: service, repository: repo)

    #expect(!viewModel.isInstalled(scenario))
    #expect(!viewModel.hasUpdate(for: scenario))

    _ = await viewModel.tryInstall(scenario)
    #expect(viewModel.isInstalled(scenario))
    #expect(!viewModel.hasUpdate(for: scenario))  // same hash

    // Bump the gallery's hash — local row hasn't been updated, so a diff exists.
    let bumped = makeGalleryScenario(hash: String(repeating: "f", count: 64))
    #expect(viewModel.hasUpdate(for: bumped))
  }
}

// MARK: - MockGalleryService

/// Deterministic in-memory `GalleryService` for ViewModel tests.
private final class MockGalleryService: GalleryService, @unchecked Sendable {
  var cachedIndex: GalleryIndex?
  var refreshResult: Result<GalleryIndex?, Error> = .success(nil)
  var yamlFor: [URL: String] = [:]
  var yamlErrorFor: [URL: GalleryServiceError] = [:]

  enum MismatchMode { case off, rejectHash }
  var mismatchMode: MismatchMode = .off

  func loadCachedIndex() throws -> GalleryIndex? {
    cachedIndex
  }

  func refreshIndex() async throws -> GalleryIndex? {
    switch refreshResult {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }

  func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
    if let err = yamlErrorFor[url] { throw err }
    guard let yaml = yamlFor[url] else {
      throw GalleryServiceError.unexpectedStatus(404)
    }
    if mismatchMode == .rejectHash {
      // swiftlint:disable:next force_unwrapping
      let actual = URLSessionGalleryService.sha256Hex(yaml.data(using: .utf8)!)
      throw GalleryServiceError.hashMismatch(expected: expectedSHA256, actual: actual)
    }
    return yaml
  }
}
