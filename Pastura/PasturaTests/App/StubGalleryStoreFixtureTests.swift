import Foundation
import Testing

@testable import Pastura

/// Coverage for `StubGalleryService.uiTestStoreGallery()` (#1612): the
/// DEBUG-only fixture used to capture App Store screenshots. Guards the two
/// invariants a screenshot regression would otherwise trip silently — the
/// tapped-without-scrolling ordering, and every entry staying executable by
/// this build's engine.
@Suite(.timeLimit(.minutes(1))) struct StubGalleryStoreFixtureTests {

  private func index() throws -> GalleryIndex {
    let service = StubGalleryService.uiTestStoreGallery()
    guard let index = try service.loadCachedIndex() else {
      Issue.record("uiTestStoreGallery() served no cached index")
      return GalleryIndex(version: 1, updatedAt: "", scenarios: [])
    }
    return index
  }

  @Test func hasTenEntries() throws {
    #expect(try index().scenarios.count == 10)
  }

  /// The Browse tab sorts `addedAt` descending then `id`
  /// (`GalleryScenarioSearch`), and the screenshot UI test taps
  /// `iiwake_battle_v1` / `iiwake_battle_v1_en` without scrolling. Asserting
  /// each is the max `addedAt` within its language is the simplest way to
  /// pin that ordering without duplicating the sort comparator here.
  @Test func iiwakeSortsFirstInEachLanguage() throws {
    let scenarios = try index().scenarios
    for language in ["ja", "en"] {
      let inLanguage = scenarios.filter { $0.effectiveLanguage == language }
      let maxAddedAt = inLanguage.map(\.addedAt).max()
      let expectedID = language == "ja" ? "iiwake_battle_v1" : "iiwake_battle_v1_en"
      let iiwake = try #require(inLanguage.first { $0.id == expectedID })
      #expect(iiwake.addedAt == maxAddedAt)
      // Every other entry in the language must sort strictly after it.
      for other in inLanguage where other.id != expectedID {
        #expect(other.addedAt < iiwake.addedAt)
      }
    }
  }

  @Test func everyEntryPassesEngineCompatibilityGate() throws {
    for scenario in try index().scenarios {
      #expect(
        EngineSchemaVersion.isCompatible(
          phases: scenario.phases, minEngineVersion: scenario.minEngineVersion),
        "\(scenario.id) must stay compatible with the current engine, or its Browse cell identifier gains an .incompatible suffix and the screenshot tap misses it"
      )
    }
  }

  @Test func iiwakeHighlightsDecodeThroughTheRealDecoder() async throws {
    let service = StubGalleryService.uiTestStoreGallery()
    let scenarios = try index().scenarios
    for id in ["iiwake_battle_v1", "iiwake_battle_v1_en"] {
      let scenario = try #require(scenarios.first { $0.id == id })
      let highlightURL = try #require(scenario.highlightURL)
      let data = try await service.fetchHighlightData(
        from: highlightURL, expectedSHA256: scenario.highlightSHA256 ?? "")
      let highlight = try JSONDecoder().decode(GalleryHighlight.self, from: data)
      #expect(highlight.scenarioRef.id == id)
      #expect(highlight.contentFilterApplied)
    }
  }
}
