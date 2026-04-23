import Foundation
import Testing

@testable import Pastura

// swiftlint:disable file_length
// Extension split per `.claude/rules/testing.md` (file_length cap). A new
// `@Suite` would race against the parent under parallel execution — extensions
// stay on the same suite so `.serialized`/`.timeLimit` traits apply uniformly.
extension ScenarioLoaderTests {

  // MARK: - Scenario top-level wrong-type errors

  /// Numeric id (YAML auto-type) previously coerced silently to "42".
  /// Strict loader throws with a wrong-type message distinguishing it from
  /// "missing field" — the prior `requireString` stringify fallback would
  /// have hidden typos like `id: 001` (YAML 1.1 auto-types to Int 1).
  @Test func throwsOnWrongTypeForRequiredString() throws {
    let yaml = """
      id: 42
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: speak_all
          prompt: "Go"
      """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'id'"))
    #expect(msg.contains("String"))
    #expect(!msg.lowercased().contains("missing"))
  }

  /// Quoted integer (`agents: "2"`) previously threw a misleading
  /// "Missing required field" error. Strict loader surfaces the real cause.
  @Test func throwsOnWrongTypeForRequiredInt() throws {
    let yaml = """
      id: test
      name: Test
      description: Test
      agents: "2"
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: speak_all
          prompt: "Go"
      """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'agents'"))
    #expect(msg.contains("Int"))
    #expect(!msg.lowercased().contains("missing"))
  }

  // MARK: - Assign target parsing (strict)

  /// Typo'd target string is rejected at parse time (was a silent `.all` default
  /// before #108 / typed `AssignTarget`).
  @Test func rejectsAssignWithUnknownTarget() {
    let yaml = makeYAMLWithAssignTarget("randomOne")  // typo of random_one
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  /// Case is significant — `target: All` was previously silently treated as
  /// the default; now rejected.
  @Test func rejectsAssignWithCapitalizedTarget() {
    let yaml = makeYAMLWithAssignTarget("All")
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  @Test func acceptsAssignWithCanonicalTargetAll() throws {
    _ = try loader.load(yaml: makeYAMLWithAssignTarget("all"))
  }

  @Test func acceptsAssignWithCanonicalTargetRandomOne() throws {
    _ = try loader.load(yaml: makeYAMLWithAssignTarget("random_one"))
  }

  // MARK: - Pairing / logic parsing (strict)

  @Test func rejectsChooseWithUnknownPairing() {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: choose
            pairing: roundRobin
            options: [a, b]
        """)
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  @Test func rejectsScoreCalcWithUnknownLogic() {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: score_calc
            logic: made_up_logic
        """)
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  // MARK: - Phase-optional field wrong-type errors (#130 item 2)

  /// `rounds: "3"` (accidentally quoted in YAML) previously coerced silently
  /// to `nil` → `subRounds` defaulted to 1 → `speak_each` ran one pass instead
  /// of three. Strict loader now throws.
  @Test func throwsOnQuotedSubRounds() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: speak_each
            prompt: "Talk"
            rounds: "3"
        """)
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'rounds'"))
    #expect(msg.contains("Int"))
  }

  /// `exclude_self: "true"` (quoted string) previously became `nil` silently;
  /// strict loader throws. Contrast with `exclude_self: yes` (bare) which is a
  /// valid YAML 1.1 boolean — see `acceptsYAML11BooleanExcludeSelf`.
  @Test func throwsOnQuotedExcludeSelf() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: vote
            prompt: "Vote"
            exclude_self: "true"
        """)
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'exclude_self'"))
    #expect(msg.contains("Bool"))
  }

  /// `exclude_self: 1` (integer) also fails strictly — no 0/1 → bool coercion.
  @Test func throwsOnIntExcludeSelf() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: vote
            prompt: "Vote"
            exclude_self: 1
        """)
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  /// YAML 1.1 treats bare `yes`/`no`/`on`/`off` as booleans. Yams follows the
  /// 1.1 spec so `exclude_self: yes` parses to `Bool(true)` — this is *not* a
  /// silent-coerce bug, it's the canonical spelling. Pinned as a positive
  /// test so a future "fix" doesn't break it.
  @Test func acceptsYAML11BooleanExcludeSelf() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: vote
            prompt: "Vote"
            exclude_self: yes
        """)
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.phases[0].excludeSelf == true)
  }

  // MARK: - parseOutputSchema strict (#130 item 3)

  /// `output: { count: 1 }` previously stringified `1` to `"1"` silently. The
  /// schema is an LLM prompt hint — a non-String value is almost always a typo.
  @Test func throwsOnNonStringOutputSchemaValue() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: speak_all
            prompt: "Go"
            output:
              statement: string
              count: 1
        """)
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("output"))
    #expect(msg.contains("'count'"))
  }

  /// `output: "string"` (scalar instead of dict) previously just skipped the
  /// schema (no-op). Strict loader throws so users catch the mis-shape.
  @Test func throwsOnNonDictOutputSchema() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: speak_all
            prompt: "Go"
            output: "string"
        """)
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  // MARK: - convertToAnyCodableValue strict (#130 item 4)

  /// Top-level scalar extraData (`count: 42`) previously silently disappeared —
  /// `convertToAnyCodableValue` returned nil and `collectExtraData` dropped it.
  /// Strict loader throws naming the offending field and listing supported shapes.
  @Test func throwsOnScalarTopLevelExtraData() throws {
    let yaml = """
      id: t
      name: T
      description: T
      agents: 2
      rounds: 1
      context: C
      personas:
        - name: A
          description: D
        - name: B
          description: D
      phases:
        - type: speak_all
          prompt: "Go"
      count: 42
      """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'count'"))
    // Error message should hint at the supported shapes so users know how to fix.
    #expect(msg.contains("String") || msg.contains("string"))
  }

  /// Quoting the scalar works — `count: "42"` parses as `.string("42")`.
  @Test func acceptsQuotedScalarTopLevelExtraData() throws {
    let yaml = """
      id: t
      name: T
      description: T
      agents: 2
      rounds: 1
      context: C
      personas:
        - name: A
          description: D
        - name: B
          description: D
      phases:
        - type: speak_all
          prompt: "Go"
      count: "42"
      """
    let scenario = try loader.load(yaml: yaml)
    if case .string(let value) = scenario.extraData["count"] {
      #expect(value == "42")
    } else {
      Issue.record("Expected .string for quoted scalar extraData")
    }
  }

  /// Mixed-type top-level array previously silently dropped the whole field
  /// (string-array conversion failed, `[[String: Any]]` conversion also failed,
  /// so the function returned nil).
  @Test func throwsOnMixedTypeExtraDataArray() throws {
    let yaml = """
      id: t
      name: T
      description: T
      agents: 2
      rounds: 1
      context: C
      personas:
        - name: A
          description: D
        - name: B
          description: D
      phases:
        - type: speak_all
          prompt: "Go"
      topics:
        - a
        - 42
      """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'topics'"))
  }

  /// `words: [{ majority: 1, minority: 2 }]` previously stringified the Int
  /// values silently (`"1"`, `"2"`). Strict loader throws — word-wolf preset
  /// authors intending a numeric tag would fail to notice the coercion.
  @Test func throwsOnNonStringValueInArrayOfDicts() throws {
    let yaml = """
      id: t
      name: T
      description: T
      agents: 2
      rounds: 1
      context: C
      personas:
        - name: A
          description: D
        - name: B
          description: D
      phases:
        - type: assign
          source: words
          target: random_one
      words:
        - majority: 1
          minority: 2
      """
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'words'"))
  }

  /// `options` containing a non-String element previously silently dropped the
  /// whole array. Strict loader throws so the typo surfaces to the user.
  @Test func throwsOnMixedTypeOptions() throws {
    let yaml = makeMinimalYAML(
      phasesBlock: """
        phases:
          - type: choose
            prompt: "Choose"
            options:
              - cooperate
              - 42
        """)
    let error = try #require(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
    guard case .scenarioValidationFailed(let msg) = error else {
      Issue.record("Expected scenarioValidationFailed, got \(error)")
      return
    }
    #expect(msg.contains("'options'"))
  }

  // MARK: - Shipped content safety net (#130 item 5)

  /// Share Board gallery YAMLs live in `docs/gallery/` (served from GitHub raw
  /// at runtime, not bundled). A loader refactor could break parsing without
  /// either the preset-loader test or the app test suite noticing until a real
  /// Share Board fetch. This pins the YAMLs to the strict loader's contract.
  ///
  /// Presets (`Pastura/Pastura/Resources/Presets/`) are already covered by
  /// `PresetLoaderTests.presetYAMLsAreParseable`; preset→serialize→parse
  /// round-trip is covered by `ScenarioSerializerTests.roundTripBokete` et al.
  @Test func galleryYAMLsLoadUnderStrictLoader() throws {
    let galleryDir = repoRoot().appendingPathComponent("docs/gallery")
    for name in ["trolley_dilemma_v1", "detective_scene_v1", "asch_conformity_v1"] {
      let url = galleryDir.appendingPathComponent("\(name).yaml")
      let yaml = try String(contentsOf: url, encoding: .utf8)
      let scenario = try loader.load(yaml: yaml)
      #expect(!scenario.phases.isEmpty, "\(name): parsed but has no phases")
    }
  }
}

/// Resolves the repo root from this file's absolute source path. Test targets
/// have host-filesystem access under iOS simulator, so `#filePath` works.
/// Path walk: this file → Engine → PasturaTests → Pastura → repo root.
private func repoRoot(file: StaticString = #filePath) -> URL {
  URL(fileURLWithPath: "\(file)")
    .deletingLastPathComponent()  // Engine/
    .deletingLastPathComponent()  // PasturaTests/
    .deletingLastPathComponent()  // Pastura/
    .deletingLastPathComponent()  // repo root
}
