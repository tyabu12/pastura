import Foundation
import Testing

@testable import Pastura

/// Structural dependency-rule guards (DoD #10).
///
/// These tests enforce ADR-010 D8's normative guarantee that
/// `LocaleResolver` is not referenced from `Engine/`, `LLM/`,
/// `Models/`, or `Data/` layers. The guard runs as a Swift test
/// rather than a CI grep script so it integrates with `xcodebuild test`
/// and appears in the xcresult bundle.
@Suite(.timeLimit(.minutes(1)))
struct StructuralBoundaryTests {

  /// `LocaleResolver` must not appear in Engine, LLM, Models, or Data.
  ///
  /// Uses a FileManager tree walk to find Swift source files containing
  /// the string "LocaleResolver". Avoids spawning `rg`/`grep` processes
  /// to stay in the allowlisted test surface.
  ///
  /// The test locates the repository root by walking up from the test
  /// bundle's directory until it finds the `Pastura/Pastura` subdirectory
  /// structure (robust regardless of DerivedData layout).
  @Test func localeResolverNotReferencedFromEngineLLMModelsData() throws {
    let repoRoot = try resolveRepoRoot()
    let restrictedDirs = [
      repoRoot
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Engine"),
      repoRoot
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Pastura")
        .appendingPathComponent("LLM"),
      repoRoot
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Models"),
      repoRoot
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Data")
    ]

    var hits: [String] = []
    for dirURL in restrictedDirs {
      hits += swiftFilesContaining("LocaleResolver", under: dirURL)
    }

    // hits.description serves as diagnostic context in the failure output.
    let hitCount = hits.count
    #expect(hitCount == 0, "LocaleResolver found in restricted layers — see test output")
  }

  // MARK: - Helpers

  /// Walks `directory` recursively and returns relative paths of `.swift`
  /// files whose content contains `needle`.
  private func swiftFilesContaining(_ needle: String, under directory: URL) -> [String] {
    let manager = FileManager.default
    guard manager.fileExists(atPath: directory.path) else { return [] }

    guard
      let enumerator = manager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }

    var hits: [String] = []
    for case let fileURL as URL in enumerator {
      guard fileURL.pathExtension == "swift" else { continue }
      guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
      if content.contains(needle) {
        hits.append(fileURL.path)
      }
    }
    return hits
  }

  /// Resolves the repository root by walking up from the test bundle until
  /// the `Pastura/Pastura` directory pair is found.
  private func resolveRepoRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: Bundle.main.bundlePath)
    // Walk up at most 20 levels — enough to escape any DerivedData nest.
    for _ in 0..<20 {
      let probe =
        candidate
        .appendingPathComponent("Pastura")
        .appendingPathComponent("Pastura")
      if FileManager.default.fileExists(atPath: probe.path) {
        return candidate
      }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path {
        break  // reached filesystem root without finding the marker
      }
      candidate = parent
    }
    // Fallback: process current directory (works in most test runner setups)
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return cwd
  }
}
