import Foundation

/// Outcome of resolving a deep-link scenario id against the gallery index.
///
/// `nonisolated` so the synthesized `Equatable`/`Sendable` conformances
/// don't inherit the project-wide `@MainActor` default — the resolver is
/// async and must be usable from any isolation context.
nonisolated public enum DeepLinkResolution: Equatable, Sendable {
  /// The id was found in either the local cache or a fresh gallery fetch.
  case found(GalleryScenario)

  /// The id is authoritatively not in the gallery we could reach.
  /// This includes the cases: fresh fetch succeeded and lacks the id, or
  /// the only available (stale) cache lacks the id and refresh failed.
  case notFound

  /// No cached gallery available and the network fetch also failed.
  /// The id might exist in the remote gallery — we just couldn't confirm.
  case networkAndCacheMiss

  /// The local cache is corrupted and the refresh attempt also failed.
  /// Distinguished from `networkAndCacheMiss` so the UI can suggest the
  /// explicit "open Share Board to refresh" recovery path.
  case corruptedCache
}

/// Resolves a deep-link scenario id to a `GalleryScenario` by consulting
/// the curated gallery index. Cache-first to stay responsive on launch,
/// falling through to a network refresh only when the cache doesn't
/// contain the id.
///
/// The resolver enforces Pastura's deep-link trust boundary: an id is
/// only ever accepted when the gallery index (local or fresh) lists it,
/// so a deep link cannot smuggle in unreviewed content.
nonisolated public struct DeepLinkResolver {
  private let galleryService: any GalleryService

  public init(galleryService: any GalleryService) {
    self.galleryService = galleryService
  }

  /// Look up `id` in the gallery index. See `DeepLinkResolution` for the
  /// possible outcomes.
  public func resolve(id: String) async -> DeepLinkResolution {
    // Cache first — the hot path for users who have recently opened
    // Share Board or HomeView (both refresh the cache behind the scenes).
    var cachedIndex: GalleryIndex?
    var cacheWasCorrupted = false
    do {
      cachedIndex = try galleryService.loadCachedIndex()
    } catch {
      // Any cache-read error is treated as "no usable cache", with the
      // corrupted variant tracked separately so we can surface a
      // distinct UI hint if the network also fails.
      cacheWasCorrupted = true
    }

    if let cached = cachedIndex,
      let scenario = cached.scenarios.first(where: { $0.id == id }) {
      return .found(scenario)
    }

    // Cache miss (or corrupted). Go to the network.
    let freshIndex: GalleryIndex?
    do {
      freshIndex = try await galleryService.refreshIndex()
    } catch {
      if cacheWasCorrupted {
        return .corruptedCache
      }
      // A stale cache we successfully read, that doesn't contain the id,
      // is authoritative enough: the maintainer's last-known gallery did
      // not include it. An empty cache + network failure gives us nothing.
      return cachedIndex == nil ? .networkAndCacheMiss : .notFound
    }

    if let fresh = freshIndex {
      if let scenario = fresh.scenarios.first(where: { $0.id == id }) {
        return .found(scenario)
      }
      return .notFound
    }

    // refreshIndex returned nil → 304 Not Modified. The cache we already
    // checked is authoritative; since we didn't find the id above, it's
    // either a .notFound or — if cache was unavailable — we have nothing.
    if cacheWasCorrupted {
      return .corruptedCache
    }
    return cachedIndex != nil ? .notFound : .networkAndCacheMiss
  }
}
