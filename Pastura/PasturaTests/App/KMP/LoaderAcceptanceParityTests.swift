import Foundation
import PasturaSharedEngine
import Testing

@testable import Pastura

/// Differential acceptance guard for ADR-023 S5-5: **every YAML the Swift
/// `ScenarioLoader` accepts, the Kotlin `PasturaSharedEngine.ScenarioLoader`
/// must accept too.**
///
/// Why this is load-bearing only from S5-5 on: the Kotlin engine is now the
/// sole fresh-run path, with no Swift fallback, while `SimulationView` still
/// validates the scenario on the **Swift** loader before starting a run. A
/// shape the two loaders disagree about therefore passes every pre-run check
/// and surfaces at run time as `.scenarioValidationFailed` — after the model
/// load, on the user's screen. The corpora below are the YAML the app actually
/// ships or accepts: bundled presets and demo presets, the ADR-020
/// shared-scenario (gallery) seeds, and the **editor round-trip** of each of
/// those (`ScenarioSerializer` output — what a user's "edit and save" writes
/// back, which is not byte-identical to the authored file).
///
/// Direction matters: this asserts Swift-accepted ⇒ Kotlin-accepted. The
/// converse is harmless (Kotlin accepting more never reaches a run, because
/// the Swift validation gate rejects it first).
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`
/// (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite(.timeLimit(.minutes(1)))
struct LoaderAcceptanceParityTests {

  /// Anchors `Bundle(for:)` on the test module so the bundled YAML resolves
  /// before `Bundle.main` (the UI runner), the same lookup
  /// `BundledPresetPlaceholderCoverageTests` uses.
  private final class Anchor {}

  private struct Corpus {
    let name: String
    let yaml: String
  }

  /// Every `.yaml` the app bundle carries: `Resources/Presets/` and
  /// `Resources/DemoPresets/` both land flat at the bundle root under the
  /// synchronized folder groups, so one enumeration covers both — and a preset
  /// added later is covered without touching this file.
  private func bundledYAML() throws -> [Corpus] {
    let bundle = Bundle(for: Anchor.self)
    // Bundle.main first: on a name collision it wins the dedupe as the
    // production truth — the shipping app bundle — over `Bundle(for:
    // Anchor.self)` (the test bundle), which is where a stale duplicate
    // copied by an older build phase would live.
    let urls =
      (Bundle.main.urls(forResourcesWithExtension: "yaml", subdirectory: nil) ?? [])
      + (bundle.urls(forResourcesWithExtension: "yaml", subdirectory: nil) ?? [])
    var seen: Set<String> = []
    var corpora: [Corpus] = []
    for url in urls {
      let name = url.lastPathComponent
      guard seen.insert(name).inserted else { continue }
      corpora.append(Corpus(name: name, yaml: try String(contentsOf: url, encoding: .utf8)))
    }
    return corpora.sorted { $0.name < $1.name }
  }

  /// The ADR-020 shared-scenario seeds committed under `docs/gallery/` — the
  /// YAML a Gallery "Try" installs verbatim. Repo-root walk copied from
  /// `GallerySeedYAMLTests`.
  private func galleryYAML() throws -> [Corpus] {
    let galleryDir = Self.repoRoot().appendingPathComponent("docs/gallery")
    let names = try FileManager.default.contentsOfDirectory(atPath: galleryDir.path)
      .filter { $0.hasSuffix(".yaml") }
      .sorted()
    return try names.map {
      Corpus(
        name: "docs/gallery/\($0)",
        yaml: try String(
          contentsOf: galleryDir.appendingPathComponent($0), encoding: .utf8))
    }
  }

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

  /// Asserts Kotlin acceptance for `yaml`, and for the editor round-trip of the
  /// scenario the Swift loader produced from it. A YAML the *Swift* loader
  /// rejects is skipped rather than recorded: the corpus is enumerated from
  /// disk, and the Swift loader's own acceptance is what other suites pin.
  ///
  /// Returns whether the comparison actually ran (i.e. the Swift loader
  /// accepted `corpus`), so a caller can assert a floor on comparisons
  /// *performed* rather than on files merely enumerated — the two diverge
  /// whenever a file in the corpus is outside this test's premise.
  @discardableResult
  private func expectKotlinAccepts(_ corpus: Corpus) -> Bool {
    let scenario: Pastura.Scenario
    do {
      scenario = try Pastura.ScenarioLoader().load(yaml: corpus.yaml)
    } catch {
      return false  // not in this test's premise — Swift rejects it, so no run reaches Kotlin
    }
    do {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: corpus.yaml)
    } catch {
      Issue.record(
        Comment(
          rawValue: "Swift accepts '\(corpus.name)' but Kotlin rejects it: \(error)"))
    }
    let roundTripped = Pastura.ScenarioSerializer().serialize(scenario)
    do {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: roundTripped)
    } catch {
      Issue.record(
        Comment(
          rawValue:
            "Kotlin rejects the editor round-trip of '\(corpus.name)': \(error)"))
    }
    return true
  }

  @Test func kotlinAcceptsEveryBundledYAMLTheSwiftLoaderAccepts() throws {
    let corpora = try bundledYAML()
    var performed = 0
    for corpus in corpora where expectKotlinAccepts(corpus) { performed += 1 }
    // Floor is the real corpus size: `Resources/Presets/*.yaml` (12) +
    // `Resources/DemoPresets/*.yaml` (6) = 18, counted 2026-09-07. A failure
    // here means the corpus shrank (or the Swift loader started rejecting a
    // file it used to accept) — update the floor after review, not before.
    #expect(performed >= 18, "expected at least 18 comparisons performed (bundled + demo presets)")
  }

  @Test func kotlinAcceptsEveryGallerySeedTheSwiftLoaderAccepts() throws {
    let corpora = try galleryYAML()
    var performed = 0
    for corpus in corpora where expectKotlinAccepts(corpus) { performed += 1 }
    // Floor is the real corpus size: `docs/gallery/*.yaml` = 46, counted
    // 2026-09-07. A failure here means the corpus shrank — update the floor
    // after review, not before.
    #expect(performed >= 46, "expected at least 46 comparisons performed (docs/gallery seeds)")
  }
}
