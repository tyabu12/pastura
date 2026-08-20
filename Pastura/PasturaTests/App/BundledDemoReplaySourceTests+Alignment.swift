import Foundation
import Testing

@testable import Pastura

// Controls for ``BundledDemoReplaySourceTests/alignmentDiagnostic(entry:phases:)``
// — the sole owner of the demo-replay phase-coordinate invariant (spec §3.3).
//
// Why a fixture rather than a shipped demo: no `Resources/DemoPresets/` preset
// uses a `conditional`, so the enumeration in the parent file cannot reach the
// conditional arm at all, and never will until such a preset is promoted to a
// demo preset. That population stays empty by design; these controls are what
// the arm has instead. They call the helper directly — the enumeration reads
// from `Bundle.main`, and there is no seam that would let it see a fixture.
//
// Extension + sibling file, NOT a new `@Suite` (`.claude/rules/testing.md`).
extension BundledDemoReplaySourceTests {

  // MARK: - Fixture

  /// `[0]=speak_all, [1]=conditional{then:[vote], else:[summarize]}, [2]=vote`.
  ///
  /// The branches hold DIFFERENT types on purpose: with identical types every
  /// branch-resolution assertion below would hold for the wrong reason, and the
  /// `branch:`-aware path would be indistinguishable from the union check it
  /// replaces. `[2]` repeats `then[0]`'s type so a wrong-level resolution has
  /// somewhere plausible to land.
  fileprivate static let conditionalScenarioYAML = """
    id: cond_align
    language: ja
    name: Alignment fixture
    description: ''
    agents: 2
    rounds: 1
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
        if: 'x > 0'
        then:
          - type: vote
            prompt: vote
            candidates: agents
        else:
          - type: summarize
            template: "closing"
      - type: vote
        prompt: vote again
        candidates: agents
    """

  fileprivate func conditionalPhases() throws -> [Phase] {
    try ScenarioLoader().load(yaml: Self.conditionalScenarioYAML).phases
  }

  fileprivate func diagnostic(_ entry: [String: Any]) throws -> String? {
    Self.alignmentDiagnostic(entry: entry, phases: try conditionalPhases())
  }

  // MARK: - Positive controls

  @Test func alignedTopLevelEntryProducesNoDiagnostic() throws {
    #expect(
      try diagnostic([
        "phase_index": 0, "phase_path": [0], "phase_type": "speak_all"
      ]) == nil)
  }

  @Test func alignedThenBranchEntryProducesNoDiagnostic() throws {
    #expect(
      try diagnostic([
        "phase_index": 1, "phase_path": [1, 0], "branch": "then", "phase_type": "vote"
      ]) == nil)
  }

  @Test func alignedElseBranchEntryProducesNoDiagnostic() throws {
    #expect(
      try diagnostic([
        "phase_index": 1, "phase_path": [1, 0], "branch": "else", "phase_type": "summarize"
      ]) == nil)
  }

  @Test func v1EntryWithoutPhasePathStillPasses() throws {
    // Back-compat: the shipped demos are all v1 and carry neither field.
    #expect(try diagnostic(["phase_index": 2, "phase_type": "vote"]) == nil)
  }

  // MARK: - Negative controls

  @Test func phasePathDisagreeingWithPhaseIndexIsCaught() throws {
    // `phase_index` IS `phase_path[0]` (spec §3.2), so this is
    // self-inconsistent without consulting the scenario at all.
    let found = try diagnostic([
      "phase_index": 0, "phase_path": [1, 0], "branch": "then", "phase_type": "vote"
    ])
    #expect(found?.contains("but phase_index is 0") == true, "got: \(found ?? "nil")")
  }

  @Test func wrongBranchIsCaught() throws {
    // The discriminating case for `branch:`. `[1, 0]` is `vote` in the then
    // branch and `summarize` in the else branch — identical path, so ONLY the
    // branch tells them apart. Without `branch:` this exact entry passes (the
    // test below pins that), which is what makes this a real control rather
    // than a restatement of the union check.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "branch": "else", "phase_type": "vote"
    ])
    #expect(found?.contains("which is summarize") == true, "got: \(found ?? "nil")")
  }

  @Test func wrongBranchIsNotCaughtWithoutTheBranchField() throws {
    // Negative control for the control above: the same misalignment is INVISIBLE
    // when `branch:` is absent, because `vote` is in the union of both branches.
    // Pinning the gap stops a later reader from believing the union check ever
    // constrained which branch ran.
    #expect(
      try diagnostic([
        "phase_index": 1, "phase_path": [1, 0], "phase_type": "vote"
      ]) == nil)
  }

  @Test func typeAbsentFromBothBranchesIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "phase_type": "speak_all"
    ])
    #expect(found?.contains("is not present") == true, "got: \(found ?? "nil")")
  }

  @Test func conditionalNamedAsItsOwnPhaseTypeIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1], "phase_type": "conditional"
    ])
    #expect(found?.contains("must name a non-conditional") == true, "got: \(found ?? "nil")")
  }

  @Test func branchIndexOutOfRangeIsCaught() throws {
    // `then` holds one phase, so `then[3]` names nothing.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 3], "branch": "then", "phase_type": "vote"
    ])
    #expect(found?.contains("that branch has 1 phases") == true, "got: \(found ?? "nil")")
  }

  @Test func overDeepPhasePathIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0, 0], "branch": "then", "phase_type": "vote"
    ])
    #expect(found?.contains("depth-1 rule") == true, "got: \(found ?? "nil")")
  }

  @Test func outOfRangePhaseIndexIsCaught() throws {
    let found = try diagnostic(["phase_index": 9, "phase_type": "vote"])
    #expect(found?.contains("out of range") == true, "got: \(found ?? "nil")")
  }

  @Test func topLevelTypeMismatchIsCaught() throws {
    let found = try diagnostic(["phase_index": 0, "phase_path": [0], "phase_type": "vote"])
    #expect(found?.contains("resolves to speak_all") == true, "got: \(found ?? "nil")")
  }
}
