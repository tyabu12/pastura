#if DEBUG

  import Foundation

  /// In-memory `GalleryService` for UI tests.
  ///
  /// Serves a preconfigured `GalleryIndex` and returns YAML bytes from an
  /// in-memory dictionary keyed by URL — no network access. Used by the
  /// `--ui-test` launch-argument branch in `PasturaApp` to keep Share Board
  /// flows deterministic. Hash verification is skipped because UI tests
  /// exercise navigation flow, not integrity checks.
  nonisolated public final class StubGalleryService: GalleryService {
    private let index: GalleryIndex
    private let yamlsByURL: [URL: String]

    public init(index: GalleryIndex, yamlsByURL: [URL: String] = [:]) {
      self.index = index
      self.yamlsByURL = yamlsByURL
    }

    public func loadCachedIndex() throws -> GalleryIndex? { index }

    public func refreshIndex() async throws -> GalleryIndex? { index }

    public func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
      guard let yaml = yamlsByURL[url] else {
        throw GalleryServiceError.unexpectedStatus(404)
      }
      return yaml
    }
  }

#endif
