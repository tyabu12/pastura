import Foundation
import Testing

@testable import Pastura

/// Smoke test: every YAML committed under `docs/gallery/` must parse via
/// `ScenarioLoader` and pass `ScenarioValidator`. Guards against shipping
/// a gallery entry that the app rejects at Try time.
@Suite(.timeLimit(.minutes(1))) struct GallerySeedYAMLTests {

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

  /// Pins the curation invariant that every gallery entry's `title`
  /// matches the corresponding YAML's `name:` field.
  ///
  /// `Route.scenarioDetail.initialName` is sourced from `scenario.title`
  /// at install time (`GalleryScenarioDetailView.pushToInstalled`) so
  /// the navigation bar shows a synchronously-known title from the
  /// first frame of the push (ADR-008). Once the local
  /// `ScenarioDetailViewModel` finishes loading, the bar transitions
  /// to `viewModel.scenario.name` (= the YAML's `name:`). If the two
  /// strings ever diverge — even by a single Unicode whitespace —
  /// the user observes a content→content title flash on install.
  /// Failing this test loudly is cheaper than the alternative
  /// (extra DB read in `pushToInstalled` to source the name from
  /// the freshly-saved local record).
  @Test func galleryTitleMatchesYAMLName() throws {
    let loader = ScenarioLoader()
    let galleryDir = Self.repoRoot().appendingPathComponent("docs/gallery")
    let indexURL = galleryDir.appendingPathComponent("gallery.json")
    let indexData = try Data(contentsOf: indexURL)
    let index = try JSONDecoder().decode(GalleryIndex.self, from: indexData)

    #expect(!index.scenarios.isEmpty, "gallery.json has no scenarios")

    for entry in index.scenarios {
      // `yamlURL` in the seed JSON is a relative file name (e.g.
      // `asch_conformity_v1.yaml`); resolve against the seed dir.
      let yamlPath =
        galleryDir
        .appendingPathComponent(entry.yamlURL.lastPathComponent)
      let yaml = try String(contentsOf: yamlPath, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      #expect(
        entry.title == scenario.name,
        """
        gallery.title (\(entry.title)) != yaml.name (\(scenario.name)) \
        for entry id=\(entry.id). \
        See ADR-008 — Route.scenarioDetail.initialName depends on this match.
        """)
    }
  }

  /// Pins ADR-005 §10.1's curation invariant: every committed seed
  /// scenario — both gallery YAMLs and bundled presets — must pass
  /// the default ``ScenarioContentValidator``.
  ///
  /// Before the input/output partition shipped, the validator's flat
  /// blocklist rejected `trolley_dilemma_v1.yaml` (`人を殺す選択`) and
  /// `detective_scene_v1.yaml` (`殺人事件`) at install time even though
  /// they are curator-endorsed ethics/roleplay content. The partition
  /// excludes the `violence` category from the input layer so these
  /// pass; this test pins that contract so a future blocklist edit
  /// that re-folds violence into the input partition fails loudly
  /// against the curated content set instead of in the App Review
  /// queue.
  @Test @MainActor func allSeedScenariosPassInputValidator() throws {
    let loader = ScenarioLoader()
    let validator = ScenarioContentValidator()

    // Gallery YAMLs (docs/gallery/*.yaml — fetched by Share Board)
    let galleryDir = Self.repoRoot().appendingPathComponent("docs/gallery")
    let galleryFiles = try FileManager.default.contentsOfDirectory(
      atPath: galleryDir.path
    ).filter { $0.hasSuffix(".yaml") }
    for name in galleryFiles {
      let yaml = try String(
        contentsOf: galleryDir.appendingPathComponent(name), encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      let findings = validator.validate(scenario)
      #expect(
        findings.isEmpty,
        "Gallery seed \(name) fails default input validator: \(findings)")
    }

    // Bundled presets (Resources/Presets/*.yaml — shipped in the app bundle)
    let testBundle = Bundle(for: DatabaseManager.self)
    for fileName in PresetLoader.presetFileNames {
      guard
        let url = testBundle.url(forResource: fileName, withExtension: "yaml")
      else {
        Issue.record("Preset \(fileName).yaml not found in test bundle")
        continue
      }
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      let findings = validator.validate(scenario)
      #expect(
        findings.isEmpty,
        "Preset \(fileName).yaml fails default input validator: \(findings)")
    }
  }

  /// Pins the curation invariant that every `gallery.json` entry's
  /// `recommendedModel` is a valid `ModelRegistry.catalog` id.
  ///
  /// A stale or mistyped `recommended_model` value in `gallery.json` would
  /// silently be ignored at runtime — `GalleryScenarioDetailView` surfaces it
  /// as the model badge, and `GalleryViewModel.tryInstall` passes it through
  /// without validation. This test catches the mismatch at curation time so
  /// it never ships to TestFlight.
  @Test func recommendedModelMatchesRegistry() throws {
    let galleryDir = Self.repoRoot().appendingPathComponent("docs/gallery")
    let indexURL = galleryDir.appendingPathComponent("gallery.json")
    let indexData = try Data(contentsOf: indexURL)
    let index = try JSONDecoder().decode(GalleryIndex.self, from: indexData)

    #expect(!index.scenarios.isEmpty, "gallery.json has no scenarios")

    let validIDs = Set(ModelRegistry.catalog.map(\.id))

    for entry in index.scenarios {
      #expect(
        validIDs.contains(entry.recommendedModel),
        """
        gallery entry id=\(entry.id) has recommendedModel="\(entry.recommendedModel)" \
        which is not in ModelRegistry.catalog. \
        Valid ids: \(validIDs.sorted().joined(separator: ", "))
        """)
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
