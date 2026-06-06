import Foundation
import Yams

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
/// committed bytes; any mismatch fails the test. To deliberately re-pin
/// shapes, temporarily remove the `.disabled(...)` trait from
/// `RoundtripBaselineTests.regenerateAllBaselines`, run that test once,
/// review the diff, then re-add the trait. (Env-gating was tried and
/// rejected — xcodebuild's xctest runner sanitises env, so the gate
/// never enables.)
enum RoundtripHelper {

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

  // MARK: - YAML-shape baselines (lossless raw-parse; Issue #220 W4 PR-C)

  /// Worktree-relative directory of the lossless **YAML-shape** baselines.
  ///
  /// These files are the raw `Yams.load(yaml:)` parse tree of each preset
  /// serialized to canonical JSON — structurally **distinct** from
  /// ``baselineDir``'s files. `baselineDir` holds the *lossy* `ScenarioLoader`
  /// output (`agentCount`, `outputSchema`, dropping `agents` / `output` /
  /// `words` / `mid_game_announcements` / `probability` / `conditional`).
  /// This directory holds the *lossless* parse that preserves every authoring
  /// key exactly as the curator wrote it.
  ///
  /// **Consumer**: the Kotlin cross-language harness
  /// (`shared/models/src/jvmTest/.../YamlFidelityEquivalenceTests.kt`) reads
  /// the SAME live preset YAML through `YamlCodec.decode` (snakeyaml-engine-kmp)
  /// and compares the canonicalized tree against these Swift/Yams baselines —
  /// discharging the spike's Tier-4 "snakeyaml-engine-kmp vs current Yams"
  /// YAML-roundtrip-fidelity question (#220).
  static var yamlBaselineDir: URL {
    baselineDir
      .deletingLastPathComponent()  // …/commonTest/resources/
      .appendingPathComponent("yaml-baselines", isDirectory: true)
  }

  /// Convert a `Yams.load`-decoded value (`Any?`) into a Foundation JSON
  /// object tree — the lossless raw-parse shape. Mirrors the Kotlin
  /// `yamlValueToJson` mapping (`shared/models/.../YamlCodec.kt`) so the two
  /// independent YAML parsers can be compared at the JSON layer.
  ///
  /// **Bool-before-number discrimination is load-bearing.** Yams bridges
  /// scalars through `NSNumber`, so `5 as? Bool` / `true as? Int` silently
  /// coerce — the type-laundering bug class already guarded in
  /// `ScenarioLoader.parseOptionalDoubleAcceptingInt`. The `is Bool` check is
  /// the reliable discriminator; without it `exclude_self: true` (word_wolf)
  /// would serialize as `1` and the cross-language equivalence claim would be
  /// silently wrong.
  ///
  /// **Float-text caveat**: `JSONSerialization` renders `Double(2.0)` as
  /// `"2"`, whereas Kotlin `JsonPrimitive(2.0).content` is `"2.0"`. No current
  /// preset has an `X.0` float (only `probability: 0.5`, which both render as
  /// `"0.5"`), so the parsers agree today. A future `X.0` float would surface
  /// as a *legitimate* Tier-4 divergence finding (a RED test), not a flake.
  static func yamlValueToJSONObject(_ value: Any?) throws -> Any {
    guard let value, !(value is NSNull) else { return NSNull() }
    if value is Bool, let bool = value as? Bool { return bool }
    if let int = value as? Int { return int }
    if let double = value as? Double { return double }
    if let string = value as? String { return string }
    if let array = value as? [Any] {
      return try array.map { try yamlValueToJSONObject($0) }
    }
    if let dict = value as? [String: Any] {
      var out: [String: Any] = [:]
      for (key, element) in dict { out[key] = try yamlValueToJSONObject(element) }
      return out
    }
    throw SimulationError.scenarioValidationFailed(
      "Unsupported YAML value type for baseline dump: \(type(of: value))")
  }

  /// Canonical JSON `Data` for an arbitrary YAML string (lossless raw-parse
  /// shape). Visible for the dumper's scalar-fidelity unit test.
  static func canonicalYAMLShapeJSON(yaml: String) throws -> Data {
    let raw = try Yams.load(yaml: yaml)
    let jsonObject = try yamlValueToJSONObject(raw)
    return try JSONSerialization.data(
      withJSONObject: jsonObject,
      options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
  }

  /// Load `<name>.yaml` from the live bundled presets directory and emit its
  /// lossless YAML-shape canonical JSON.
  static func encodedYamlShapeBaseline(presetName: String) throws -> Data {
    let yamlURL = presetsDir.appendingPathComponent("\(presetName).yaml")
    let yaml = try String(contentsOf: yamlURL, encoding: .utf8)
    return try canonicalYAMLShapeJSON(yaml: yaml)
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

  /// `.yaml.json` suffix marks the file as the JSON of the YAML parse —
  /// distinct from `baselines/<name>.json` (the lossy ScenarioLoader shape).
  static func yamlBaselineURL(name: String) -> URL {
    yamlBaselineDir.appendingPathComponent("\(name).yaml.json", isDirectory: false)
  }

  static func writeYamlShapeBaseline(_ data: Data, name: String) throws {
    try FileManager.default.createDirectory(
      at: yamlBaselineDir, withIntermediateDirectories: true)
    try data.write(to: yamlBaselineURL(name: name))
  }

  static func readYamlShapeBaseline(name: String) throws -> Data {
    try Data(contentsOf: yamlBaselineURL(name: name))
  }
}
