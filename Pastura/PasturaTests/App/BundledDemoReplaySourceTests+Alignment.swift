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

  /// `[0]=speak_all, [1]=conditional{then:[vote, speak_all], else:[summarize]},
  /// [2]=vote`.
  ///
  /// Three properties are load-bearing, each because a simpler fixture makes
  /// some assertion below hold for the wrong reason:
  ///
  /// - the branches hold DIFFERENT types at index 0, or `branch:`-aware
  ///   resolution would agree with the branch-blind union check everywhere;
  /// - `then` holds TWO phases, so `speak_all` is in the union of both
  ///   branches while NOT being what index 0 names — the only shape that can
  ///   tell an indexed check from a union check (measured: with one phase per
  ///   branch, reverting the indexed check to a union broke no test);
  /// - `[2]` repeats `then[0]`'s type, so a wrong-level resolution has
  ///   somewhere plausible to land.
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
          - type: speak_all
            prompt: say
            output:
              statement: string
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

  @Test func typeAbsentFromTheIndexedSubPhaseIsCaught() throws {
    // Nested path, no `branch` — the exporter's shape. `[1, 0]` is `vote` in
    // then and `summarize` in else, so `speak_all` matches neither — even
    // though it IS in the union of both branches, as `then[1]`. That gap is
    // the whole difference between this check and the v1 one below.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "phase_type": "speak_all"
    ])
    #expect(
      found?.contains("across the branches") == true, "got: \(found ?? "nil")")
  }

  @Test func typeAbsentFromBothBranchesIsCaughtInTheV1Shape() throws {
    // No nested path at all: the entry says only "somewhere inside this
    // conditional", so membership in the union is all the data supports.
    // `score_calc` rather than `speak_all` — the latter is now in the union
    // (it is `then[1]`), which is exactly what makes the indexed check above
    // stronger than this one.
    let found = try diagnostic(["phase_index": 1, "phase_type": "score_calc"])
    #expect(found?.contains("is not present") == true, "got: \(found ?? "nil")")
  }

  @Test func subPhaseIndexBeyondEveryBranchIsCaughtWithoutBranchField() throws {
    // Without `branch` the range check used to be skipped entirely — the union
    // of both branches' TYPES accepts any index. `YAMLReplayExporter` emits a
    // nested `phase_path` and can never emit `branch`, so that writer's output
    // was the unowned case.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 7], "phase_type": "summarize"
    ])
    #expect(
      found?.contains("no branch holds that many phases") == true,
      "got: \(found ?? "nil")")
  }

  @Test func conditionalAsItsOwnLeafTypeIsAccepted() throws {
    // Correct by spec §3.2: `phase_type` is the type of the phase AT
    // `phase_path`, and `[1]` is the conditional. `ConditionalHandler.execute`
    // emits `evaluation.warnings` as `.summary` before `.conditionalEvaluated`
    // — i.e. at exactly this coordinate — so a demo of a condition naming a
    // runtime-absent variable produces this entry. The gate used to reject it,
    // contradicting the spec it enforces.
    #expect(
      try diagnostic([
        "phase_index": 1, "phase_path": [1], "phase_type": "conditional"
      ]) == nil)
  }

  @Test func conditionalNestedInsideABranchIsCaught() throws {
    // The depth-1 rule: a branch sub-phase can never be a conditional, so at a
    // NESTED path the type is wrong however the outer phase resolves.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "phase_type": "conditional"
    ])
    #expect(
      found?.contains("depth-1 rule forbids") == true, "got: \(found ?? "nil")")
  }

  @Test func unknownPhaseTypeUnderAConditionalIsCaught() throws {
    // Split out of the conditional check above; `PhaseType(rawValue:)` failing
    // is a different fault from naming the conditional itself.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "phase_type": "not_a_phase"
    ])
    #expect(
      found?.contains("must name a non-conditional") == true, "got: \(found ?? "nil")")
  }

  @Test func nestedPathUnderANonConditionalPhaseIsCaught() throws {
    // Only a conditional has sub-phases. `[0, 1]` names one under `speak_all`,
    // which cannot exist — and the reader would still split it into its own
    // `.phaseStarted`, inflating the progress denominator.
    let found = try diagnostic([
      "phase_index": 0, "phase_path": [0, 1], "phase_type": "speak_all"
    ])
    #expect(
      found?.contains("which has no sub-phases") == true, "got: \(found ?? "nil")")
  }

  @Test func branchIndexOutOfRangeIsCaught() throws {
    // `then` holds two phases, so `then[3]` names nothing.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 3], "branch": "then", "phase_type": "vote"
    ])
    #expect(found?.contains("that branch holds 2 phase(s)") == true, "got: \(found ?? "nil")")
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

  // MARK: - Mistyped optional fields
  //
  // Both fields are optional, so the obvious spelling is `if let x = entry[k]
  // as? T`, which SKIPS the check when the cast fails rather than failing it.
  // `YAMLReplaySource.resolvePhasePath` fails on the identical cast and falls
  // back to `[phase_index]`, so a wrong-typed `phase_path` would be invisible
  // in both places at once — these pin the presence-keyed form instead.

  @Test func phasePathOfWrongElementTypeIsCaught() throws {
    for badPath in [["1", "0"] as [Any], [true, 0] as [Any]] {
      let found = try diagnostic([
        "phase_index": 1, "phase_path": badPath, "phase_type": "vote"
      ])
      #expect(found?.contains("not a list of Int") == true, "got: \(found ?? "nil")")
    }
  }

  @Test func parsedBooleanPhasePathElementIsCaught() throws {
    // The mirror of the curator's arm (j), where the guard is load-bearing
    // because `isinstance(True, int)` is True in Python. The Swift question is
    // NOT whether `[Any]` casts to `[Int]` — the arm above settles that — but
    // which scalar type the PARSER hands back: a Swift `Bool` fails `as? Int`,
    // an `NSNumber` would succeed and resolve to phase 1. Every other fixture
    // in this file is hand-built and so cannot see that boundary, which is why
    // this one goes through Yams.
    let demo = """
      schema_version: 2
      turns:
        - round: 1
          phase_index: 1
          phase_path: [true, 0]
          phase_type: vote
          agent: Alice
          fields: {}
      """
    let raw = try BundledDemoReplaySourceTests.parseYAMLAsDictionary(demo)
    let entry = try #require((raw["turns"] as? [[String: Any]])?.first)
    let found = Self.alignmentDiagnostic(entry: entry, phases: try conditionalPhases())
    #expect(found?.contains("not a list of Int") == true, "got: \(found ?? "nil")")
  }

  @Test func explicitlyNullPhasePathIsCaught() throws {
    // Yams renders a bare `phase_path:` as `NSNull`, which is PRESENT — so the
    // presence-keyed check rejects it where the loader would benignly fall
    // back. Deliberate: a writer that emitted the key meant to say something.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": NSNull(), "phase_type": "vote"
    ])
    #expect(found?.contains("not a list of Int") == true, "got: \(found ?? "nil")")
  }

  @Test func phasePathThatIsNotAListIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": "1,0", "phase_type": "vote"
    ])
    #expect(found?.contains("not a list of Int") == true, "got: \(found ?? "nil")")
  }

  @Test func branchOfWrongTypeIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "branch": 0, "phase_type": "vote"
    ])
    #expect(found?.contains("not a String") == true, "got: \(found ?? "nil")")
  }

  // MARK: - Remaining diagnostics
  //
  // Every `return` in `alignmentDiagnostic` / `conditionalDiagnostic` needs a
  // control, or the ones without are the same unverified-guard defect the
  // negative controls above exist to prevent.

  @Test func emptyPhasePathIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [Int](), "phase_type": "vote"
    ])
    #expect(found?.contains("phase_path is empty") == true, "got: \(found ?? "nil")")
  }

  @Test func branchNamingNeitherThenNorElseIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "branch": "maybe", "phase_type": "vote"
    ])
    #expect(found?.contains("neither 'then' nor 'else'") == true, "got: \(found ?? "nil")")
  }

  @Test func branchWithoutANestedPathIsCaught() throws {
    // Reachable from writer drift, not just from a hand-edit: a curator that
    // emitted `branch:` while the path stayed top-level lands here.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1], "branch": "then", "phase_type": "vote"
    ])
    #expect(
      found?.contains("without a nested phase_path") == true, "got: \(found ?? "nil")")
  }

  @Test func missingPhaseIndexIsCaught() throws {
    let found = try diagnostic(["phase_type": "vote"])
    #expect(found?.contains("non-Int phase_index") == true, "got: \(found ?? "nil")")
  }

  @Test func missingPhaseTypeIsCaught() throws {
    let found = try diagnostic(["phase_index": 0])
    #expect(found?.contains("non-String phase_type") == true, "got: \(found ?? "nil")")
  }
}
