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
///
/// Source walking and repo-root resolution live in ``SourceTreeProbe``,
/// shared with `MutedSweepLedgerTests`. The root resolution moved there from
/// a bundle-walk that never resolved on a simulator runner — read that type's
/// doc comment before changing it, and keep the scanned-file floor below.
@Suite(.timeLimit(.minutes(1)))
struct StructuralBoundaryTests {

  /// `LocaleResolver` must not be *referenced* from Engine, LLM, Models, or
  /// Data. Prose naming it is fine — `Models/Scenario.swift` documents which
  /// callers seed a language from it, and that is not a dependency.
  ///
  /// Uses a FileManager tree walk to find Swift source files containing
  /// the string "LocaleResolver". Avoids spawning `rg`/`grep` processes
  /// to stay in the allowlisted test surface.
  @Test func localeResolverNotReferencedFromEngineLLMModelsData() throws {
    let restrictedDirs = ["Engine", "LLM", "Models", "Data"].map {
      SourceTreeProbe.appSourceRoot.appending(path: $0)
    }

    var hits: [String] = []
    for dirURL in restrictedDirs {
      // Non-vacuity floor, asserted **per layer**. Absent it, an unresolvable
      // repo root scans four directories that do not exist, finds nothing, and
      // the guard reports a clean tree — which is exactly what it did until
      // #1448 measured it. Summing across the four would close only that half:
      // one layer renamed or moved still leaves the total positive while the
      // guard silently stops covering it.
      let layer = SourceTreeProbe.swiftFiles(under: dirURL)
      #expect(!layer.isEmpty, "\(dirURL.lastPathComponent) resolved to no sources")

      hits += SourceTreeProbe.swiftFilesContaining("LocaleResolver", under: dirURL)
    }

    #expect(
      hits.isEmpty,
      "LocaleResolver found in restricted layers: \(hits)")
  }

  /// Control for the comment filter the guard above leans on, in the direction
  /// that filter can fail silently: a filter that stopped filtering would
  /// report `Models/Scenario.swift`, whose only mentions are doc-comment prose.
  /// A filter that ate every line is caught by the scanned-file floor plus the
  /// positive arm here.
  @Test func theCommentFilterDiscriminatesRatherThanNullifies() throws {
    let models = SourceTreeProbe.appSourceRoot.appending(path: "Models")
    let scenario = try String(
      contentsOf: models.appending(path: "Scenario.swift"), encoding: .utf8)

    #expect(
      scenario.contains("LocaleResolver"),
      "Scenario.swift no longer mentions LocaleResolver — this control has lost its fixture")
    #expect(SourceTreeProbe.swiftFilesContaining("LocaleResolver", under: models).isEmpty)
    #expect(
      !SourceTreeProbe.swiftFilesContaining("Scenario", under: models).isEmpty,
      "a needle every Models file carries matched nothing — the filter is nullifying")
  }
}
