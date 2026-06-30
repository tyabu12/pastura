import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `GalleryScenarioTests` for the ADR-010 index-side
// `language` dimension. An `extension` (NOT a new `@Suite`) per
// `.claude/rules/testing.md` — a fresh suite would run in parallel and is
// reserved for shared-state isolation, which these pure decode tests don't need.
extension GalleryScenarioTests {

  /// A feed entry declaring `language: "en"` decodes it verbatim and
  /// `effectiveLanguage` reflects it (no fallback).
  @Test func decodeWithLanguageEn() throws {
    let json = """
      {
        "id": "asch_conformity_v1_en",
        "title": "Asch Conformity",
        "category": "social_psychology",
        "description": "desc",
        "author": "tyabu12",
        "recommended_model": "gemma-4-e2b-q4-k-m",
        "estimated_inferences": 10,
        "language": "en",
        "yaml_url": "https://example.com/asch_en.yaml",
        "yaml_sha256": "abc123",
        "added_at": "2026-06-29"
      }
      """
    let scenario = try JSONDecoder().decode(GalleryScenario.self, from: Data(json.utf8))
    #expect(scenario.language == "en")
    #expect(scenario.effectiveLanguage == "en")
  }

  /// Backward-compat: an index entry predating the `language` key (e.g. an
  /// old cached `gallery.json` on-device) must still decode, with `language
  /// == nil` and `effectiveLanguage` defaulting to `"ja"` — the launch
  /// gallery is all-Japanese. Same lenient-decode posture as
  /// `agentCount` / `rounds` / `phases`.
  @Test func decodeWithoutLanguageDefaultsToJa() throws {
    let json = """
      {
        "id": "legacy_v1",
        "title": "Legacy",
        "category": "experimental",
        "description": "desc",
        "author": "tyabu12",
        "recommended_model": "gemma-4-e2b-q4-k-m",
        "estimated_inferences": 8,
        "yaml_url": "https://example.com/legacy.yaml",
        "yaml_sha256": "deadbeef",
        "added_at": "2026-04-15"
      }
      """
    let scenario = try JSONDecoder().decode(GalleryScenario.self, from: Data(json.utf8))
    #expect(scenario.language == nil)
    #expect(scenario.effectiveLanguage == "ja")
  }
}
