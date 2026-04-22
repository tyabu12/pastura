import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct DeepLinkResolverTests {

  // MARK: - Fixtures

  private static func makeScenario(id: String) -> GalleryScenario {
    GalleryScenario(
      id: id,
      title: "Scenario \(id)",
      category: .experimental,
      description: "test fixture",
      author: "test",
      recommendedModel: "mock",
      estimatedInferences: 1,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/\(id).yaml")!,
      yamlSHA256: String(repeating: "0", count: 64),
      addedAt: "2026-04-22")
  }

  private static func makeIndex(_ scenarios: [GalleryScenario]) -> GalleryIndex {
    GalleryIndex(version: 1, updatedAt: "2026-04-22T00:00:00Z", scenarios: scenarios)
  }

  // MARK: - Tests

  @Test func cacheHitReturnsFoundWithoutRefresh() async {
    let target = Self.makeScenario(id: "asch_v1")
    let service = MockGalleryService()
    service.cachedIndex = Self.makeIndex([target])
    service.refreshResult = .success(Self.makeIndex([]))  // would be observable if called

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    #expect(result == .found(target))
    #expect(service.refreshCallCount == 0, "refresh must not be called when cache has the id")
  }

  @Test func afterRefreshReturnsFoundWhenCacheMisses() async {
    let target = Self.makeScenario(id: "asch_v1")
    let service = MockGalleryService()
    service.cachedIndex = nil
    service.refreshResult = .success(Self.makeIndex([target]))

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    #expect(result == .found(target))
    #expect(service.refreshCallCount == 1)
  }

  @Test func notFoundWhenFreshIndexLacksId() async {
    let service = MockGalleryService()
    service.cachedIndex = nil
    service.refreshResult = .success(Self.makeIndex([Self.makeScenario(id: "other")]))

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    #expect(result == .notFound)
  }

  @Test func notFoundWhenRefreshFailsButStaleCacheWithoutId() async {
    let service = MockGalleryService()
    service.cachedIndex = Self.makeIndex([Self.makeScenario(id: "other")])
    service.refreshResult = .failure(GalleryServiceError.invalidResponse)

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    // Stale cache authoritatively says the id isn't in the gallery we know about.
    #expect(result == .notFound)
  }

  @Test func networkAndCacheMissWhenBothUnavailable() async {
    let service = MockGalleryService()
    service.cachedIndex = nil
    service.refreshResult = .failure(GalleryServiceError.invalidResponse)

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    #expect(result == .networkAndCacheMiss)
  }

  @Test func corruptedCacheRecoversViaSuccessfulRefresh() async {
    let target = Self.makeScenario(id: "asch_v1")
    let service = MockGalleryService()
    service.cachedIndexError = GalleryServiceError.corruptedCache
    service.refreshResult = .success(Self.makeIndex([target]))

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    #expect(result == .found(target))
  }

  @Test func corruptedCacheReturnsErrorWhenRefreshAlsoFails() async {
    let service = MockGalleryService()
    service.cachedIndexError = GalleryServiceError.corruptedCache
    service.refreshResult = .failure(GalleryServiceError.invalidResponse)

    let resolver = DeepLinkResolver(galleryService: service)
    let result = await resolver.resolve(id: "asch_v1")

    #expect(result == .corruptedCache)
  }
}

// MARK: - MockGalleryService

/// Deterministic in-memory `GalleryService` for resolver tests.
///
/// Tracks refresh call count so tests can assert the cache-hit fast path
/// avoids the network entirely. Deliberately separate from the
/// `MockGalleryService` in `ShareBoardViewModelTests.swift` — that one is
/// `private` to its test file and carries ViewModel-specific hooks.
private final class MockGalleryService: GalleryService, @unchecked Sendable {
  var cachedIndex: GalleryIndex?
  var cachedIndexError: Error?
  var refreshResult: Result<GalleryIndex?, Error> = .success(nil)
  private(set) var refreshCallCount = 0

  func loadCachedIndex() throws -> GalleryIndex? {
    if let error = cachedIndexError { throw error }
    return cachedIndex
  }

  func refreshIndex() async throws -> GalleryIndex? {
    refreshCallCount += 1
    switch refreshResult {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }

  func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
    // Resolver does not fetch YAML; placeholder for protocol conformance.
    throw GalleryServiceError.unexpectedStatus(404)
  }
}
