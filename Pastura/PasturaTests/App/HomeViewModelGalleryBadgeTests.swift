import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct HomeViewModelGalleryBadgeTests {

  private func makeRepo() throws -> GRDBScenarioRepository {
    let manager = try DatabaseManager.inMemory()
    return GRDBScenarioRepository(dbWriter: manager.dbWriter)
  }

  private func makeIndex(_ items: [(id: String, hash: String)]) -> GalleryIndex {
    GalleryIndex(
      version: 1, updatedAt: "2026-04-14T00:00:00Z",
      scenarios: items.map { tuple in
        GalleryScenario(
          id: tuple.id, title: tuple.id, category: .experimental,
          description: "", author: "",
          recommendedModel: ModelRegistry.gemma4E2B.id, estimatedInferences: 0,
          // swiftlint:disable:next force_unwrapping
          yamlURL: URL(string: "https://example.com/\(tuple.id).yaml")!,
          yamlSHA256: tuple.hash, addedAt: "2026-04-14")
      })
  }

  @Test func badgesPopulateWhenLocalHashDiffers() async throws {
    let repo = try makeRepo()
    // One local gallery-sourced row with stale hash
    try repo.save(
      ScenarioRecord(
        id: "x", name: "X", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date(),
        sourceType: ScenarioSourceType.gallery, sourceId: "x",
        sourceHash: "OLD"))
    // One local plain row — should be ignored by badge logic.
    try repo.save(
      ScenarioRecord(
        id: "local", name: "Local", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date()))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    let service = StubGalleryService(cachedIndex: makeIndex([("x", "NEW"), ("local", "whatever")]))
    await viewModel.refreshGalleryUpdateBadges(using: service)
    #expect(viewModel.galleryUpdateBadges == ["x"])
  }

  @Test func badgesEmptyWhenHashesMatch() async throws {
    let repo = try makeRepo()
    try repo.save(
      ScenarioRecord(
        id: "x", name: "X", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date(),
        sourceType: ScenarioSourceType.gallery, sourceId: "x",
        sourceHash: "MATCH"))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    let service = StubGalleryService(cachedIndex: makeIndex([("x", "MATCH")]))
    await viewModel.refreshGalleryUpdateBadges(using: service)
    #expect(viewModel.galleryUpdateBadges.isEmpty)
  }

  @Test func badgesEmptyWhenNoCache() async throws {
    let repo = try makeRepo()
    try repo.save(
      ScenarioRecord(
        id: "x", name: "X", yamlDefinition: "yaml",
        isPreset: false, createdAt: Date(), updatedAt: Date(),
        sourceType: ScenarioSourceType.gallery, sourceId: "x",
        sourceHash: "OLD"))

    let viewModel = HomeViewModel(repository: repo)
    await viewModel.loadScenarios()

    let service = StubGalleryService(cachedIndex: nil)
    await viewModel.refreshGalleryUpdateBadges(using: service)
    #expect(viewModel.galleryUpdateBadges.isEmpty)
  }
}

private final class StubGalleryService: GalleryService, @unchecked Sendable {
  private let index: GalleryIndex?

  init(cachedIndex: GalleryIndex?) {
    self.index = cachedIndex
  }

  func loadCachedIndex() throws -> GalleryIndex? { index }
  func refreshIndex() async throws -> GalleryIndex? { nil }
  func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
    throw GalleryServiceError.unexpectedStatus(404)
  }
}
