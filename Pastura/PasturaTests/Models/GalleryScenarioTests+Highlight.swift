import Foundation
import Testing

@testable import Pastura

// Split out of `GalleryScenarioTests` to keep the parent suite under
// swiftlint's `type_body_length` cap — sibling-file `extension` of the same
// suite, per testing.md § "Splitting a Suite Across Files".
extension GalleryScenarioTests {

  // MARK: - highlightURL / highlightSHA256 (optional, ADR-029)

  @Test func decodeWithHighlight() throws {
    let json = """
      {
        "id": "asch_conformity_v1",
        "title": "アッシュの同調実験",
        "category": "social_psychology",
        "description": "desc",
        "author": "tyabu12",
        "recommended_model": "gemma-4-e2b-q4-k-m",
        "estimated_inferences": 5,
        "yaml_url": "https://example.com/asch.yaml",
        "yaml_sha256": "deadbeef",
        "added_at": "2026-08-06",
        "highlight_url": "https://example.com/highlights/asch_conformity_v1.json",
        "highlight_sha256": "cafef00d"
      }
      """
    let scenario = try JSONDecoder().decode(GalleryScenario.self, from: Data(json.utf8))
    #expect(
      scenario.highlightURL?.absoluteString
        == "https://example.com/highlights/asch_conformity_v1.json")
    #expect(scenario.highlightSHA256 == "cafef00d")
  }

  /// Backward compat: an entry without highlight fields (older feed, or a
  /// scenario the ADR-029 spoiler policy excludes) must decode with both
  /// `nil` — same posture as `featured` / `minEngineVersion` / etc.
  @Test func decodeWithoutHighlightYieldsNil() throws {
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
    #expect(scenario.highlightURL == nil)
    #expect(scenario.highlightSHA256 == nil)
  }
}
