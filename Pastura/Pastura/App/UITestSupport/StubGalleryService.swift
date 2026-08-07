#if DEBUG

  import Foundation

  /// In-memory `GalleryService` for UI tests.
  ///
  /// Serves a preconfigured `GalleryIndex` and returns YAML bytes from an
  /// in-memory dictionary keyed by URL — no network access. Used by the
  /// `--ui-test` launch-argument branch in `PasturaApp` to keep Shared Scenarios
  /// flows deterministic. Hash verification is skipped because UI tests
  /// exercise navigation flow, not integrity checks.
  nonisolated public final class StubGalleryService: GalleryService {
    /// How the stub answers `loadCachedIndex` / `refreshIndex`, so the
    /// screenshot tour can reach the gallery sad-paths (#811).
    public enum Behavior: Sendable {
      /// Both methods serve `index` — the default, populated path.
      case serveIndex
      /// `loadCachedIndex` returns nil AND `refreshIndex` throws, so
      /// `SharedScenariosViewModel` lands on `.empty` ("Gallery Unavailable").
      /// Both halves are load-bearing: a nil cache alone leaves `.loading`,
      /// and a throwing refresh over a served cache yields `.offlineWithCache`
      /// — only the pair reaches `.empty`.
      case offline
    }

    private let index: GalleryIndex
    private let yamlsByURL: [URL: String]
    private let highlightsByURL: [URL: Data]
    private let behavior: Behavior

    public init(
      index: GalleryIndex,
      yamlsByURL: [URL: String] = [:],
      highlightsByURL: [URL: Data] = [:],
      behavior: Behavior = .serveIndex
    ) {
      self.index = index
      self.yamlsByURL = yamlsByURL
      self.highlightsByURL = highlightsByURL
      self.behavior = behavior
    }

    public func loadCachedIndex() throws -> GalleryIndex? {
      switch behavior {
      case .serveIndex: return index
      case .offline: return nil
      }
    }

    public func refreshIndex() async throws -> GalleryIndex? {
      switch behavior {
      case .serveIndex: return index
      case .offline: throw GalleryServiceError.unexpectedStatus(503)
      }
    }

    public func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
      guard let yaml = yamlsByURL[url] else {
        throw GalleryServiceError.unexpectedStatus(404)
      }
      return yaml
    }

    public func fetchHighlightData(from url: URL, expectedSHA256: String) async throws -> Data {
      // Empty for every fixture except ``uiTestHighlightGallery()``, so the
      // default canary detail screen keeps no highlight section and the flows
      // that tap through it are unaffected by its height.
      guard let data = highlightsByURL[url] else {
        throw GalleryServiceError.unexpectedStatus(404)
      }
      return data
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
      language: ja
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

    /// The canary gallery entry. Both fixtures build from this so an edit to
    /// the canary cannot drift between them; only the highlight-bearing one
    /// passes the two optional arguments.
    ///
    /// Hashes are placeholders — the stub serves from memory and skips SHA-256
    /// verification.
    private static func canaryScenario(
      rounds: Int? = nil, highlight: (url: URL, sha256: String)? = nil
    ) -> GalleryScenario {
      GalleryScenario(
        id: "ui_test_canary",
        title: "UITest Canary",
        category: .experimental,
        description: "Minimal fixture for UI tests.",
        author: "UITest",
        recommendedModel: ModelRegistry.gemma4E2B.id,
        estimatedInferences: 2,
        yamlURL: canaryYAMLURL,
        yamlSHA256: "0000000000000000000000000000000000000000000000000000000000000000",
        addedAt: "2026-04-15",
        rounds: rounds,
        highlightURL: highlight?.url,
        highlightSHA256: highlight?.sha256
      )
    }

    /// Returns a `StubGalleryService` seeded with a single installable scenario
    /// used by the canary navigation test.
    public static func uiTestPreset() -> StubGalleryService {
      let index = GalleryIndex(
        version: 1, updatedAt: "2026-04-15", scenarios: [canaryScenario()])
      return StubGalleryService(
        index: index, yamlsByURL: [canaryYAMLURL: canaryYAML])
    }

    /// Canonical highlight URL for ``uiTestHighlightGallery()``. Served from
    /// memory like ``canaryYAMLURL``.
    public static let canaryHighlightURL: URL = {
      guard let url = URL(string: "stub://gallery/canary-highlight.json") else {
        fatalError("Canary highlight URL literal failed to parse")
      }
      return url
    }()

    /// A schema-shaped highlight for the canary scenario (ADR-029 schema 1).
    ///
    /// Shaped to make `GalleryHighlightRunFigure` render **every** branch it
    /// has: two speakers so two avatar colour slots resolve, a round change so
    /// a `PasturaStreamDivider` is drawn, and both speak phases so the per-row
    /// `PhaseTypeLabel` differs between rows. `content_filter_applied` is
    /// `true` and the phases are renderable, because the loader's fail-closed
    /// gates would otherwise hide the section and the render check would pass
    /// while drawing nothing.
    ///
    /// ⚠️ **Not gate-valid content, and deliberately so.** It cites two rounds
    /// and a `speak_each` phase where ``canaryYAML`` declares `rounds: 1` and a
    /// single `speak_all` — `check-gallery-entry.sh` would reject that pairing.
    /// Nothing in-app cross-checks the two (the stub skips hash verification
    /// for the same reason), and bending the shared canary YAML to match would
    /// perturb the navigation and focus-mode flows that install and run it. Do
    /// not copy this file as an example of a well-formed highlight.
    public static let canaryHighlightJSON: Data = Data(
      """
      {
        "schema_version": 1,
        "scenario_ref": {
          "id": "ui_test_canary",
          "yaml_sha256": "0000000000000000000000000000000000000000000000000000000000000000"
        },
        "source": {
          "model": "gemma-4-e2b-q4-k-m",
          "run_id": "uitest-0001",
          "generated_at": "2026-08-07"
        },
        "excerpt": [
          {
            "agent": "Alice", "round": 1, "phase": "speak_all",
            "phase_index": 0, "source_field": "statement",
            "text": "はじめまして、よろしく。"
          },
          {
            "agent": "Bob", "round": 1, "phase": "speak_all",
            "phase_index": 0, "source_field": "statement",
            "text": "こちらこそ。まずは様子を見たい。"
          },
          {
            "agent": "Alice", "round": 2, "phase": "speak_each",
            "phase_index": 0, "source_field": "statement",
            "text": "では、そろそろ本題に入ろう。"
          }
        ],
        "yaml_hook": {
          "fragment": "  - name: Alice\\n    description: First UI test persona.",
          "caption": "説明を書き換えると口調が変わる。"
        },
        "teaser": "この続きはアプリで。",
        "window_override": false,
        "content_filter_applied": true
      }
      """.utf8)

    /// Gallery whose canary entry carries a highlight, so the run figure
    /// actually renders (`--ui-test-seed-highlight`).
    ///
    /// Separate from ``uiTestPreset()`` deliberately. The highlight section is
    /// tall, and the flows that tap `galleryDetail.tryButton` reach it without
    /// scrolling — seeding a highlight into the default fixture would push that
    /// button off-screen and break navigation tests that have nothing to do
    /// with highlights.
    ///
    /// `rounds: 2` on the entry is load-bearing: it is what makes the head and
    /// the divider render their `Round N / M` form rather than the total-less
    /// fallback, so both label branches are exercised.
    public static func uiTestHighlightGallery() -> StubGalleryService {
      let scenario = canaryScenario(
        rounds: 2,
        highlight: (
          url: canaryHighlightURL,
          sha256: "1111111111111111111111111111111111111111111111111111111111111111"
        ))
      let index = GalleryIndex(
        version: 1, updatedAt: "2026-04-15", scenarios: [scenario])
      return StubGalleryService(
        index: index,
        yamlsByURL: [canaryYAMLURL: canaryYAML],
        highlightsByURL: [canaryHighlightURL: canaryHighlightJSON])
    }

    /// Gallery that loads successfully but ships **zero** scenarios — drives
    /// the `.loaded` state's empty `scenariosCard` (`.galleryEmpty` reason,
    /// "No scenarios available yet"). Used by `--ui-test-seed-empty-gallery`
    /// for the screenshot tour (#811). Distinct from ``uiTestOfflineGallery()``
    /// (which renders the `.empty` LoadState's "Gallery Unavailable").
    public static func uiTestEmptyGallery() -> StubGalleryService {
      let index = GalleryIndex(version: 1, updatedAt: "2026-04-15", scenarios: [])
      return StubGalleryService(index: index)
    }

    /// Gallery that cannot load and has no cache — drives the `.empty`
    /// LoadState ("Gallery Unavailable" + Retry). Used by
    /// `--ui-test-seed-gallery-offline` for the screenshot tour (#811). The
    /// `index` is never served (``Behavior/offline`` returns nil / throws), so
    /// an empty placeholder is fine.
    public static func uiTestOfflineGallery() -> StubGalleryService {
      let index = GalleryIndex(version: 1, updatedAt: "2026-04-15", scenarios: [])
      return StubGalleryService(index: index, behavior: .offline)
    }
  }

#endif
