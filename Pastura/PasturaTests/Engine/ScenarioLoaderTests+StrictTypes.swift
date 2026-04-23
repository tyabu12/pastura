import Testing

@testable import Pastura

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
}
