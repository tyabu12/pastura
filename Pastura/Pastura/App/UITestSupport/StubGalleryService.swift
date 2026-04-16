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

  // MARK: - UI test fixture

  extension StubGalleryService {
    /// Canonical URL used by the canary fixture. Exposed so tests can assert
    /// against it if needed; never reached because `StubGalleryService` serves
    /// from memory.
    public static let canaryYAMLURL: URL = {
      // Hardcoded literal — failure is structurally impossible, but the
      // project bans `!` so the guard makes the invariant explicit.
      guard let url = URL(string: "stub://gallery/canary.yaml") else {
        fatalError("Canary YAML URL literal failed to parse")
      }
      return url
    }()

    /// A minimal gallery YAML that parses cleanly through `ScenarioLoader`.
    /// Designed to reach `SimulationView` — running the simulation to
    /// completion is not a goal (MockLLMService has no canned responses).
    public static let canaryYAML: String = """
      id: ui_test_canary
      name: UITest Canary
      description: Minimal scenario used by PasturaUITests navigation regression coverage.
      agents: 2
      rounds: 1
      context: UI test canary scenario.
      personas:
        - name: Alice
          description: First UI test persona.
        - name: Bob
          description: Second UI test persona.
      phases:
        - type: speak_all
          prompt: Say hello.
          output:
            statement: string
      """

    /// Returns a `StubGalleryService` seeded with a single installable scenario
    /// used by the canary navigation test. Hash is intentionally left as a
    /// placeholder — the stub skips SHA-256 verification.
    public static func uiTestPreset() -> StubGalleryService {
      let scenario = GalleryScenario(
        id: "ui_test_canary",
        title: "UITest Canary",
        category: .experimental,
        description: "Minimal fixture for UI tests.",
        author: "UITest",
        recommendedModel: "mock",
        estimatedInferences: 2,
        yamlURL: canaryYAMLURL,
        yamlSHA256: "0000000000000000000000000000000000000000000000000000000000000000",
        addedAt: "2026-04-15"
      )
      let index = GalleryIndex(
        version: 1, updatedAt: "2026-04-15", scenarios: [scenario])
      return StubGalleryService(
        index: index, yamlsByURL: [canaryYAMLURL: canaryYAML])
    }
  }

#endif
