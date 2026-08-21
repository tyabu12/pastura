import Foundation
import Testing

@testable import Pastura

// Tests for schema-v2 `phase_path` resolution in ``YAMLReplaySource``
// (Issue #1505) — ordering, phase-boundary detection, and the
// `.phaseStarted` payload, plus the v1 `[phase_index]` fallback.
//
// Extension + sibling file, NOT a new `@Suite` — a second suite would race
// against the original on shared state (see `.claude/rules/testing.md`).
// Split out rather than appended to a sibling because both were already near
// SwiftLint's 400-line `file_length` cap, which `--strict` promotes to an
// error. Deliberately no line count here: it would be a snapshot that rots
// silently, while the constraint it is evidence for does not.
extension YAMLReplaySourceTests {

  // MARK: - Fixture

  /// One `speak_all`, then a `conditional` whose two branches each hold a
  /// `summarize`, then a trailing `speak_all`. Real branch structure so the
  /// `[1, 0]` paths below address something that actually exists — the
  /// loader itself never resolves a path against the scenario (spec §3.3
  /// gives that invariant to `BundledDemoReplaySourceTests`), so the shape
  /// is documentation for the next reader rather than something under test.
  fileprivate static let conditionalScenarioYAML = """
    id: cond1
    language: ja
    name: Conditional fixture
    description: ''
    agents: 2
    rounds: 2
    context: ''
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
    phases:
      - type: speak_all
        prompt: say
        output:
          statement: string
      - type: conditional
        if: 'score_alice > 0'
        then:
          - type: summarize
            template: "then branch"
        else:
          - type: summarize
            template: "else branch"
      - type: speak_all
        prompt: say again
        output:
          statement: string
    """

  fileprivate func makeConditionalScenario() throws -> Scenario {
    try ScenarioLoader().load(yaml: Self.conditionalScenarioYAML)
  }

  fileprivate func phaseStartedPaths(_ events: [PacedEvent]) -> [[Int]] {
    events.compactMap { paced in
      if case .phaseStarted(_, let path) = paced.event { return path }
      return nil
    }
  }

  // MARK: - `.phaseStarted` payload

  @Test func phasePathReachesPhaseStartedVerbatim() throws {
    let yaml = """
      schema_version: 2
      turns:
        - round: 1
          phase_index: 1
          phase_path: [1, 0]
          branch: then
          phase_type: summarize
          agent: Alice
          fields: { statement: 'from the then branch' }
      """
    let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())

    // The v1 shape would have collapsed this to `[1]` — the enclosing
    // conditional — losing which phase actually spoke.
    #expect(phaseStartedPaths(source.plannedEvents()) == [[1, 0]])
  }

  @Test func absentPhasePathFallsBackToPhaseIndex() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 2
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'v1 entry' }
      """
    let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())

    #expect(phaseStartedPaths(source.plannedEvents()) == [[2]])
  }

  @Test func unusablePhasePathFallsBackToPhaseIndex() throws {
    // An empty array and a non-Int array both fail `as? [Int]` / the
    // non-empty check. Falling back keeps the lenient load-time posture
    // (spec §3.3) rather than throwing on a coordinate the CI gate owns.
    for badPath in ["[]", "['a']"] {
      let yaml = """
        schema_version: 2
        turns:
          - round: 1
            phase_index: 2
            phase_path: \(badPath)
            phase_type: speak_all
            agent: Alice
            fields: { statement: 'x' }
        """
      let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())
      #expect(phaseStartedPaths(source.plannedEvents()) == [[2]])
    }
  }

  // MARK: - Ordering

  @Test func phasePathOrdersLexicographicallyNotByTopLevelIndex() throws {
    // Source order is scrambled; `[1, 0]` must land between `[0]` and `[2]`.
    // Under the old integer key the branch entry compared as plain `1`, so
    // this particular ordering also held — the case that did NOT is the
    // boundary test below.
    let yaml = """
      schema_version: 2
      turns:
        - round: 1
          phase_index: 2
          phase_path: [2]
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'third' }
        - round: 1
          phase_index: 0
          phase_path: [0]
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'first' }
        - round: 1
          phase_index: 1
          phase_path: [1, 0]
          branch: else
          phase_type: summarize
          agent: Alice
          fields: { statement: 'second' }
      """
    let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())

    let statements = source.plannedEvents().compactMap { paced -> String? in
      if case .agentOutput(_, let output, _) = paced.event { return output.fields["statement"] }
      return nil
    }
    #expect(statements == ["first", "second", "third"])
    #expect(phaseStartedPaths(source.plannedEvents()) == [[0], [1, 0], [2]])
  }

  // MARK: - Boundary detection

  @Test func siblingBranchPhasesOfOneTypeGetSeparatePhaseStarted() throws {
    // The discriminating case. Two sub-phases of the SAME type under one
    // conditional differ only in the path's second component, so the old
    // `(phase_index, phase_type)` boundary key saw one phase and synthesised
    // a single `.phaseStarted`. `phase_path` splits them.
    let yaml = """
      schema_version: 2
      turns:
        - round: 1
          phase_index: 1
          phase_path: [1, 0]
          branch: then
          phase_type: summarize
          agent: Alice
          fields: { statement: 'first sub-phase' }
        - round: 1
          phase_index: 1
          phase_path: [1, 1]
          branch: then
          phase_type: summarize
          agent: Bob
          fields: { statement: 'second sub-phase' }
      """
    let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())

    #expect(phaseStartedPaths(source.plannedEvents()) == [[1, 0], [1, 1]])
  }

  @Test func repeatedPhasePathDoesNotResynthesizePhaseStarted() throws {
    // Negative control for the test above: identical paths and types must
    // still collapse to ONE `.phaseStarted`, or the boundary check would be
    // firing on source position rather than on the coordinate.
    let yaml = """
      schema_version: 2
      turns:
        - round: 1
          phase_index: 1
          phase_path: [1, 0]
          phase_type: summarize
          agent: Alice
          fields: { statement: 'a' }
        - round: 1
          phase_index: 1
          phase_path: [1, 0]
          phase_type: summarize
          agent: Bob
          fields: { statement: 'b' }
      """
    let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())

    #expect(phaseStartedPaths(source.plannedEvents()) == [[1, 0]])
  }

  // MARK: - Code-phase events

  @Test func codePhaseEventsResolvePhasePathToo() throws {
    // `phase_path` is parsed by both `parseTurn` and `parseCodePhaseEvent`;
    // covering only turns would leave the second call site unmeasured.
    let yaml = """
      schema_version: 2
      turns: []
      code_phase_events:
        - round: 1
          phase_index: 1
          phase_path: [1, 0]
          branch: else
          phase_type: summarize
          summary: 'branch summary'
      """
    let source = try YAMLReplaySource(yaml: yaml, scenario: makeConditionalScenario())

    #expect(phaseStartedPaths(source.plannedEvents()) == [[1, 0]])
  }

  // MARK: - Schema version acceptance
  //
  // Here rather than in the parent file, which runs nearer SwiftLint's
  // 400-line `file_length` cap. No line count here either, per this file's
  // header.
  // Every other fixture in the parent stays at v1, which is this branch's
  // v1-back-compat coverage — do not sweep them to v2.

  @Test func acceptsSchemaVersion2() throws {
    let yaml = """
      schema_version: 2
      turns: []
      """
    let scenario = try makeScenario()
    // Widened acceptance (spec §3.5) — v2 must not throw, even though no
    // writer emits it yet. `phase_path` / `branch` parsing is out of scope
    // for this change; an empty `turns:` is enough to prove acceptance.
    #expect(throws: Never.self) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }

  /// `true` must NOT be read as `1`. Python's `True == 1` made the drift
  /// guard's old `!= 1` check accept `schema_version: true`; this pins the
  /// Swift side so the claim that the two loaders agree is measured rather
  /// than reasoned from Yams' bridging behaviour.
  @Test func throwsOnBooleanSchemaVersion() throws {
    let yaml = """
      schema_version: true
      turns: []
      """
    let scenario = try makeScenario()
    #expect(throws: YAMLReplaySourceError.unsupportedSchemaVersion(nil)) {
      _ = try YAMLReplaySource(yaml: yaml, scenario: scenario)
    }
  }
}
