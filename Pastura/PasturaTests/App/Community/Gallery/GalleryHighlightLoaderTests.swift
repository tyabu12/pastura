import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct GalleryHighlightLoaderTests {

  // MARK: - Fixtures

  // swiftlint:disable:next force_unwrapping
  private static let highlightURL = URL(string: "https://example.com/h/asch_v1.json")!
  private static let highlightHash = String(repeating: "a", count: 64)

  /// Mirrors the shape of `docs/gallery/highlights/asch_conformity_v1.json`.
  private static func highlightJSON(
    schemaVersion: Int = 1,
    contentFilterApplied: Bool = true,
    excerptCount: Int = 2,
    phases: [String]? = nil
  ) -> Data {
    // `phases`, when supplied, drives one entry per element so a test can mix
    // known and unknown phase strings; otherwise every entry is `speak_each`.
    let entryPhases = phases ?? Array(repeating: "speak_each", count: max(excerptCount, 0))
    let entries = entryPhases.enumerated().map { index, phase in
      """
      {
        "agent": "サクラ\(index)",
        "round": 1,
        "phase": "\(phase)",
        "phase_index": 0,
        "source_field": "statement",
        "text": "答えはCです。"
      }
      """
    }
    let json = """
      {
        "schema_version": \(schemaVersion),
        "scenario_ref": {
          "id": "asch_v1",
          "yaml_sha256": "\(String(repeating: "b", count: 64))"
        },
        "source": {
          "model": "gemma-4-e2b-q4-k-m",
          "run_id": "20260806-000253-bd2a",
          "generated_at": "2026-08-06"
        },
        "excerpt": [\(entries.joined(separator: ","))],
        "yaml_hook": {
          "fragment": "description: 自信家",
          "caption": "性格を書き換えてみよう"
        },
        "teaser": "多数派の答えに引きずられるか。",
        "window_override": false,
        "content_filter_applied": \(contentFilterApplied)
      }
      """
    return Data(json.utf8)
  }

  private func makeScenario(
    highlightURL: URL? = GalleryHighlightLoaderTests.highlightURL,
    highlightSHA256: String? = GalleryHighlightLoaderTests.highlightHash
  ) -> GalleryScenario {
    GalleryScenario(
      id: "asch_v1",
      title: "Asch",
      category: .socialPsychology,
      description: "desc",
      author: "t",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 10,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/asch_v1.yaml")!,
      yamlSHA256: String(repeating: "c", count: 64),
      addedAt: "2026-08-06",
      highlightURL: highlightURL,
      highlightSHA256: highlightSHA256)
  }

  // MARK: - Pairing

  @Test func bothFieldsAbsentSkipsFetch() async {
    let service = HighlightStubGalleryService()
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario(highlightURL: nil, highlightSHA256: nil))

    #expect(loader.highlight == nil)
    #expect(service.highlightFetchCount == 0)
  }

  @Test func urlWithoutHashSkipsFetch() async {
    let service = HighlightStubGalleryService()
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario(highlightSHA256: nil))

    #expect(loader.highlight == nil)
    #expect(service.highlightFetchCount == 0)
  }

  @Test func hashWithoutURLSkipsFetch() async {
    let service = HighlightStubGalleryService()
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario(highlightURL: nil))

    #expect(loader.highlight == nil)
    #expect(service.highlightFetchCount == 0)
  }

  // MARK: - Fetch failures

  @Test func hashMismatchHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .failure(
      GalleryServiceError.hashMismatch(expected: "a", actual: "b"))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
    #expect(service.highlightFetchCount == 1)
  }

  @Test func responseTooLargeHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .failure(GalleryServiceError.responseTooLarge(limit: 65_536))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  @Test func genericFetchErrorHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .failure(GalleryServiceError.unexpectedStatus(503))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  // MARK: - Verification funnel

  @Test func undecodableBytesHideSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Data("not json at all".utf8))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  @Test func unknownSchemaVersionHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON(schemaVersion: 2))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  @Test func unattestedContentFilterHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON(contentFilterApplied: false))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  @Test func emptyExcerptHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON(excerptCount: 0))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  /// Version skew: a highlight published after a new `PhaseType` lands, read by
  /// an app build that predates the case (ADR-029 revisit trigger 1). The
  /// excerpt is a quotation, so a phase this build cannot name hides the whole
  /// section rather than dropping the line out of the passage.
  @Test func unmappableExcerptPhaseHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON(phases: ["interpretive_dance"]))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  /// A phase that maps fine but declares no primary output field is equally
  /// unrenderable: `AgentOutputRow` looks the line up by that field name, so
  /// the row would show a speaker above an empty bubble. `summarize` is a code
  /// phase, so `ScenarioConventions.primaryField(for:)` returns `nil` for it.
  @Test func mappableButFieldlessExcerptPhaseHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON(phases: ["summarize"]))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  /// The guard is `allSatisfy`, not a check of the first entry — one bad line
  /// anywhere in the passage hides it. Without this case a first-entry-only
  /// check would still pass `unmappableExcerptPhaseHidesSection` above.
  @Test func oneUnknownPhaseAmongKnownOnesHidesSection() async {
    let service = HighlightStubGalleryService()
    service.result = .success(
      Self.highlightJSON(phases: ["speak_each", "interpretive_dance", "speak_all"]))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight == nil)
  }

  // MARK: - Success

  /// Positive control for the two hide cases above: the same fixture path with
  /// every phase mappable still publishes, so they fail on the phase check
  /// rather than on the explicit `phases:` argument itself.
  @Test func mappablePhaseVarietyIsPublished() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON(phases: ["speak_each", "speak_all"]))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight?.excerpt.count == 2)
  }

  @Test func validHighlightIsPublished() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON())
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())

    #expect(loader.highlight?.schemaVersion == 1)
    #expect(loader.highlight?.excerpt.count == 2)
    #expect(loader.highlight?.scenarioRef.id == "asch_v1")
    #expect(loader.highlight?.teaser == "多数派の答えに引きずられるか。")
  }

  @Test func secondLoadAfterFailureCanSucceed() async {
    let service = HighlightStubGalleryService()
    service.result = .failure(GalleryServiceError.unexpectedStatus(500))
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())
    #expect(loader.highlight == nil)

    service.result = .success(Self.highlightJSON())
    await loader.load(for: makeScenario())
    #expect(loader.highlight != nil)
  }

  @Test func failedLoadClearsAPreviousHighlight() async {
    let service = HighlightStubGalleryService()
    service.result = .success(Self.highlightJSON())
    let loader = GalleryHighlightLoader(galleryService: service)

    await loader.load(for: makeScenario())
    #expect(loader.highlight != nil)

    service.result = .failure(GalleryServiceError.unexpectedStatus(500))
    await loader.load(for: makeScenario())
    #expect(loader.highlight == nil)
  }
}

// MARK: - HighlightStubGalleryService

/// Deterministic `GalleryService` stub for ``GalleryHighlightLoader`` tests.
/// Only `fetchHighlightData` is exercised; the rest are unreachable stubs.
/// Named distinctly from `StubVMGalleryService` — both are module-scope.
private final class HighlightStubGalleryService: GalleryService, @unchecked Sendable {
  var result: Result<Data, Error> = .failure(GalleryServiceError.unexpectedStatus(404))
  private(set) var highlightFetchCount = 0

  func loadCachedIndex() throws -> GalleryIndex? { nil }

  func refreshIndex() async throws -> GalleryIndex? { nil }

  func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
    throw GalleryServiceError.unexpectedStatus(404)
  }

  func fetchHighlightData(from url: URL, expectedSHA256: String) async throws -> Data {
    highlightFetchCount += 1
    return try result.get()
  }
}
