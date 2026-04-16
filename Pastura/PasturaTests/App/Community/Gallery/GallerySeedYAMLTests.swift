import Foundation
import Testing

@testable import Pastura

/// Smoke test: every YAML committed under `docs/gallery/` must parse via
/// `ScenarioLoader` and pass `ScenarioValidator`. Guards against shipping
/// a gallery entry that the app rejects at Try time.
@Suite struct GallerySeedYAMLTests {

  @Test func allSeedYAMLsParseAndValidate() throws {
    let loader = ScenarioLoader()
    let validator = ScenarioValidator()

    let galleryDir = Self.repoRoot().appendingPathComponent("docs/gallery")
    let files = try FileManager.default.contentsOfDirectory(
      atPath: galleryDir.path
    ).filter { $0.hasSuffix(".yaml") }

    #expect(files.count >= 3, "Expected at least 3 seed gallery YAMLs")

    for name in files {
      let yaml = try String(
        contentsOf: galleryDir.appendingPathComponent(name), encoding: .utf8)
      let scenario: Scenario
      do {
        scenario = try loader.load(yaml: yaml)
      } catch {
        Issue.record("Failed to load \(name): \(error)")
        continue
      }
      do {
        _ = try validator.validate(scenario)
      } catch {
        Issue.record("Validation failed for \(name): \(error)")
      }
    }
  }

  /// Resolve the repo root relative to this test file. `#filePath` expands
  /// at compile time to the absolute source path; we walk up until we find
  /// the directory that contains `docs/gallery`.
  private static func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.path != "/" {
      url.deleteLastPathComponent()
      let candidate = url.appendingPathComponent("docs/gallery")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return url
      }
    }
    return url
  }
}
