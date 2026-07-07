import Foundation
import Testing

@testable import Pastura

// Split out of `GalleryScenarioTests` to keep the parent suite under
// swiftlint's `type_body_length` cap (testing.md § "Splitting a Suite Across
// Files"). Sibling-file `extension` of the same suite — NOT a new `@Suite`,
// which would run in parallel and defeat the shared-suite ordering.
extension GalleryScenarioTests {

  // MARK: - minEngineVersion (optional, ADR-020 D3 declared escape hatch)

  @Test func decodeWithMinEngineVersion() throws {
    let json = """
      {
        "id": "future_v1",
        "title": "Future",
        "category": "experimental",
        "description": "desc",
        "author": "tyabu12",
        "recommended_model": "gemma-4-e2b-q4-k-m",
        "estimated_inferences": 5,
        "min_engine_version": 3,
        "yaml_url": "https://example.com/future.yaml",
        "yaml_sha256": "deadbeef",
        "added_at": "2026-07-07"
      }
      """
    let scenario = try JSONDecoder().decode(GalleryScenario.self, from: Data(json.utf8))
    #expect(scenario.minEngineVersion == 3)
  }

  /// Forward-compat: a feed predating the `min_engine_version` key (or an
  /// older app reading a newer feed) must decode with `minEngineVersion ==
  /// nil` — the entry is treated as unconstrained. Same posture as
  /// `agentCount` / `rounds` / `phases`.
  @Test func decodeWithoutMinEngineVersionYieldsNil() throws {
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
    #expect(scenario.minEngineVersion == nil)
  }
}
