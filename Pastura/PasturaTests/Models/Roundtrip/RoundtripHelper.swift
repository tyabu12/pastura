import Foundation

@testable import Pastura

/// Cross-language baseline JSON generator for the KMP spike (Issue #220
/// W2 PR-B) Swift↔Kotlin wire-shape equivalence harness.
///
/// **Role**: produces the canonical Swift-side JSON that the Kotlin
/// roundtrip harness (`shared/models/src/commonTest/kotlin/.../CanonicalEquivalenceTests.kt`)
/// loads as fixtures. The helper is the source of truth for "what JSON
/// shape would Swift's `JSONEncoder` emit from the equivalent in-memory
/// instance?" — running on Apple Foundation, on actual Pastura types,
/// using the production path where one exists (`ScenarioLoader` for YAML
/// preset → `Scenario`).
///
/// **Drift model**: baseline JSON files are committed under
/// `shared/models/src/commonTest/resources/baselines/`. The companion
/// `RoundtripBaselineTests` regenerate in-memory and diff against the
/// committed bytes; any mismatch fails the test. Regeneration is gated
/// behind `PASTURA_REGENERATE_BASELINES=1` (see
/// `RoundtripBaselineTests.regenerateAllBaselines`) so a developer can
/// pin a deliberate shape change in one motion.
///
/// **Nonisolated discipline**: this enum has only `static` methods with
/// auto-synthesized closures — no custom `Equatable`/`Hashable` witnesses,
/// no Pattern 2 trigger. Marked `nonisolated` at the type level
/// nonetheless to match the surrounding Models-test convention; it costs
/// nothing and surfaces if someone later adds a custom witness.
nonisolated enum RoundtripHelper {

  /// Worktree-relative baseline directory, computed from `#filePath`.
  ///
  /// Walks up from `Pastura/PasturaTests/Models/Roundtrip/RoundtripHelper.swift`
  /// to the worktree root, then into the KMP module's commonTest resources.
  /// Recomputing per-call is cheap and avoids ordering issues with module
  /// initialisation; cache if profiling ever shows it matters.
  static var baselineDir: URL {
    let thisFile = URL(fileURLWithPath: #filePath)
    let worktreeRoot =
      thisFile
      .deletingLastPathComponent()  // Roundtrip/
      .deletingLastPathComponent()  // Models/
      .deletingLastPathComponent()  // PasturaTests/
      .deletingLastPathComponent()  // Pastura/ (Xcode project dir)
      .deletingLastPathComponent()  // worktree root
    return worktreeRoot.appendingPathComponent(
      "shared/models/src/commonTest/resources/baselines",
      isDirectory: true)
  }

  /// Worktree-relative directory of bundled preset YAML files.
  static var presetsDir: URL {
    let thisFile = URL(fileURLWithPath: #filePath)
    let worktreeRoot =
      thisFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return worktreeRoot.appendingPathComponent(
      "Pastura/Pastura/Resources/Presets",
      isDirectory: true)
  }

  /// Canonical JSON encoder used for all Swift-side baselines.
  ///
  /// - `.sortedKeys` matches the Kotlin canonicalizer's Stage 1 key sort —
  ///   one less divergence axis to debug at compare time.
  /// - `.prettyPrinted` for committed-file diff legibility; the canonical
  ///   harness compares semantic JsonElement equivalence, not byte-equal
  ///   text, so whitespace differences don't matter for the equivalence
  ///   claim.
  /// - `.withoutEscapingSlashes` keeps URL fields readable (`gallery.json`
  ///   has `https://` URLs).
  private static var canonicalEncoder: JSONEncoder {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    return enc
  }

  // MARK: - Scenario presets (4 base ja fixtures)

  /// Bundled ja-locale preset names that PR-B's baseline set covers.
  /// Excludes `_en` siblings — the canonicalizer is text-blind, so
  /// `_en` would only restate the structural assertions of the ja
  /// version with different string values.
  static let basePresetNames: [String] = [
    "prisoners_dilemma",
    "word_wolf",
    "bokete",
    "target_score_race"
  ]

  /// Load `<name>.yaml` from the bundled presets directory, decode via
  /// `ScenarioLoader` (production path), and encode as canonical JSON.
  static func encodedScenarioBaseline(presetName: String) throws -> Data {
    let yamlURL = presetsDir.appendingPathComponent("\(presetName).yaml")
    let yaml = try String(contentsOf: yamlURL, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)
    return try canonicalEncoder.encode(scenario)
  }

  // MARK: - Synthetic fixtures (GalleryIndex, CodePhaseEventPayload)

  /// Synthetic `GalleryIndex` instance covering the production snake_case
  /// wire shape. Mirrors what `gallery.json` would emit from a curated
  /// scenario entry — small enough to read, broad enough to exercise every
  /// `@SerialName`-annotated property in both Swift CodingKeys and Kotlin.
  static func syntheticGalleryIndex() -> GalleryIndex {
    GalleryIndex(
      version: 1,
      updatedAt: "2026-05-19T00:00:00Z",
      scenarios: [
        GalleryScenario(
          id: "asch_conformity_v1",
          title: "Asch Conformity Experiment",
          category: .socialPsychology,
          description: "Group pressure on individual judgment.",
          author: "Pastura Curators",
          recommendedModel: "gemma_4_e2b",
          estimatedInferences: 42,
          yamlURL: URL(string: "https://example.com/gallery/asch_conformity_v1.yaml")!,
          yamlSHA256: "abc123def456",
          addedAt: "2026-05-01"),
        GalleryScenario(
          id: "prisoners_dilemma_v2",
          title: "Iterated Prisoner's Dilemma",
          category: .gameTheory,
          description: "Multi-round cooperate/defect dynamics.",
          author: "Pastura Curators",
          recommendedModel: "qwen_3_4b",
          estimatedInferences: 28,
          yamlURL: URL(string: "https://example.com/gallery/prisoners_dilemma_v2.yaml")!,
          yamlSHA256: "def789abc012",
          addedAt: "2026-05-15")
      ])
  }

  static func encodedGalleryIndexBaseline() throws -> Data {
    try canonicalEncoder.encode(syntheticGalleryIndex())
  }

  /// Synthetic CodePhaseEventPayload array covering all 7 cases plus the
  /// critical `eventInjected(event: nil)` miss case (Q6 day-1 sanity).
  /// Swift's auto-synth Codable for associated-value enums produces the
  /// outer-wrap form `{"<caseName>":{<payload>}}` — this is the canonical
  /// form Kotlin's Stage 3 lifts toward.
  static func syntheticCodePhaseEventPayloads() -> [CodePhaseEventPayload] {
    [
      .elimination(agent: "ada", voteCount: 3),
      .scoreUpdate(scores: ["ada": 10, "bob": 5]),
      .summary(text: "Round 1 complete"),
      .voteResults(
        votes: ["ada": "bob", "bob": "ada"],
        tallies: ["ada": 1, "bob": 1]),
      .pairingResult(
        agent1: "ada", action1: "cooperate",
        agent2: "bob", action2: "defect"),
      .assignment(agent: "ada", value: "wolf"),
      .eventInjected(event: nil),  // critical: miss case
      .eventInjected(event: "earthquake")  // hit case for completeness
    ]
  }

  static func encodedCodePhaseEventPayloadsBaseline() throws -> Data {
    try canonicalEncoder.encode(syntheticCodePhaseEventPayloads())
  }

  // MARK: - I/O

  static func baselineURL(name: String) -> URL {
    baselineDir.appendingPathComponent("\(name).json", isDirectory: false)
  }

  static func writeBaseline(_ data: Data, name: String) throws {
    let dir = baselineDir
    try FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true)
    let url = baselineURL(name: name)
    try data.write(to: url)
  }

  static func readBaseline(name: String) throws -> Data {
    try Data(contentsOf: baselineURL(name: name))
  }
}
