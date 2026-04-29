import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct GalleryScenarioTests {

  // MARK: - Fixtures

  private static let sampleJSON = """
    {
      "version": 1,
      "updated_at": "2026-04-14T00:00:00Z",
      "scenarios": [
        {
          "id": "asch_conformity_v1",
          "title": "アッシュの同調実験",
          "category": "social_psychology",
          "description": "4人のサクラが…",
          "author": "tyabu12",
          "recommended_model": "gemma-4-e2b-q4-k-m",
          "estimated_inferences": 15,
          "yaml_url": "https://raw.githubusercontent.com/tyabu12/pastura/main/docs/gallery/asch_conformity_v1.yaml",
          "yaml_sha256": "abc123",
          "added_at": "2026-04-14"
        }
      ]
    }
    """

  private static var sampleIndex: GalleryIndex {
    GalleryIndex(
      version: 1,
      updatedAt: "2026-04-14T00:00:00Z",
      scenarios: [sampleScenario]
    )
  }

  private static var sampleScenario: GalleryScenario {
    GalleryScenario(
      id: "asch_conformity_v1",
      title: "アッシュの同調実験",
      category: .socialPsychology,
      description: "4人のサクラが…",
      author: "tyabu12",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 15,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(
        string:
          "https://raw.githubusercontent.com/tyabu12/pastura/main/docs/gallery/asch_conformity_v1.yaml"
      )!,
      yamlSHA256: "abc123",
      addedAt: "2026-04-14"
    )
  }

  // MARK: - GalleryIndex round-trip

  @Test func galleryIndexRoundTrip() throws {
    let original = Self.sampleIndex
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GalleryIndex.self, from: data)
    #expect(decoded == original)
  }

  // MARK: - GalleryScenario round-trip

  @Test func galleryScenarioRoundTrip() throws {
    let original = Self.sampleScenario
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GalleryScenario.self, from: data)
    #expect(decoded == original)
  }

  // MARK: - Decode from realistic JSON

  @Test func decodeFromRealisticJSON() throws {
    let data = Data(Self.sampleJSON.utf8)
    let index = try JSONDecoder().decode(GalleryIndex.self, from: data)

    #expect(index.version == 1)
    #expect(index.updatedAt == "2026-04-14T00:00:00Z")
    #expect(index.scenarios.count == 1)

    let scenario = try #require(index.scenarios.first)
    #expect(scenario.id == "asch_conformity_v1")
    #expect(scenario.title == "アッシュの同調実験")
    #expect(scenario.category == .socialPsychology)
    #expect(scenario.description == "4人のサクラが…")
    #expect(scenario.author == "tyabu12")
    #expect(scenario.recommendedModel == ModelRegistry.gemma4E2B.id)
    #expect(scenario.estimatedInferences == 15)
    #expect(
      scenario.yamlURL.absoluteString
        == "https://raw.githubusercontent.com/tyabu12/pastura/main/docs/gallery/asch_conformity_v1.yaml"
    )
    #expect(scenario.yamlSHA256 == "abc123")
    #expect(scenario.addedAt == "2026-04-14")
  }

  // MARK: - GalleryCategory unknown raw value

  @Test func unknownCategoryThrows() {
    let json = """
      {
        "id": "test",
        "title": "Test",
        "category": "unknown_category",
        "description": "desc",
        "author": "author",
        "recommended_model": "model",
        "estimated_inferences": 5,
        "yaml_url": "https://example.com/test.yaml",
        "yaml_sha256": "deadbeef",
        "added_at": "2026-04-14"
      }
      """
    let data = Data(json.utf8)
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(GalleryScenario.self, from: data)
    }
  }

  // MARK: - GalleryCategory raw values coverage

  @Test func galleryCategoryRawValues() {
    let expectedRaws = [
      "social_psychology",
      "game_theory",
      "ethics",
      "roleplay",
      "creative",
      "experimental"
    ]
    let actualRaws = GalleryCategory.allCases.map { $0.rawValue }
    #expect(Set(actualRaws) == Set(expectedRaws))
    #expect(GalleryCategory.allCases.count == 6)
  }

  // MARK: - GalleryCategory known raw values decode correctly

  @Test func galleryCategoryDecodeAllCases() throws {
    let cases: [(String, GalleryCategory)] = [
      ("social_psychology", .socialPsychology),
      ("game_theory", .gameTheory),
      ("ethics", .ethics),
      ("roleplay", .roleplay),
      ("creative", .creative),
      ("experimental", .experimental)
    ]
    for (rawValue, expected) in cases {
      let json = "\"\(rawValue)\""
      let decoded = try JSONDecoder().decode(GalleryCategory.self, from: Data(json.utf8))
      #expect(decoded == expected)
    }
  }
}
