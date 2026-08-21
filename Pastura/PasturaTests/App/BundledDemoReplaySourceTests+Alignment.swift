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
  ///   resolution would agree with the branch-blind INDEXED check everywhere;
  /// - `then` holds TWO phases, so `speak_all` is in the union of both
  ///   branches while NOT being what index 0 names. That separates the indexed
  ///   check from a union check on TYPE, which one phase per branch cannot do:
  ///   there the candidates at index j always ARE the whole union. It is not
  ///   the only such shape — `subPhaseIndexBeyondEveryBranchIsCaught…`
  ///   separates them on RANGE with one phase per branch — but range and type
  ///   are separate exits and both need a control;
  /// - `[2]` repeats `then[0]`'s type, so a wrong-level resolution has
  ///   somewhere plausible to land.
  ///
  /// Internal rather than file-scoped: the sibling `+Branch.swift` extension
  /// reads this and ``diagnostic(_:)``, and file scope does not reach an
  /// extension in another file (`.claude/rules/testing.md` § "Splitting a
  /// Suite Across Files" records the same trap for `private`). Folded into
  /// this `///` block rather than sitting under it as `//` — a plain comment
  /// between a doc comment and its declaration detaches the doc and trips
  /// `orphaned_doc_comment` (`.claude/rules/build-traps.md`).
  static let conditionalScenarioYAML = """
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

  func conditionalPhases() throws -> [Phase] {
    try ScenarioLoader().load(yaml: Self.conditionalScenarioYAML).phases
  }

  func diagnostic(_ entry: [String: Any]) throws -> String? {
    Self.alignmentDiagnostic(entry: entry, phases: try conditionalPhases())
  }

  // MARK: - Positive controls

  @Test func alignedTopLevelEntryProducesNoDiagnostic() throws {
    #expect(
      try diagnostic([
        "phase_index": 0, "phase_path": [0], "phase_type": "speak_all"
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

  @Test func typeAbsentFromBothBranchesIsCaughtInTheV1Shape() throws {
    // No nested path at all: the entry says only "somewhere inside this
    // conditional", so membership in the union is all the data supports.
    // `score_calc` rather than `speak_all` — the latter is now in the union
    // (it is `then[1]`), which is exactly what makes
    // `typeAbsentFromTheIndexedSubPhaseIsCaught` in `+Branch.swift` stronger
    // than this one. Named rather than pointed at: a "below"/"above" reference
    // survives neither a reorder nor the file split that stranded this pair.
    let found = try diagnostic(["phase_index": 1, "phase_type": "score_calc"])
    #expect(found?.contains("is not present") == true, "got: \(found ?? "nil")")
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

  @Test func conditionalAsLeafIsAcceptedInTheV1Shape() throws {
    // The pre-v6 exporter row omits `phase_path` entirely, so this — not the
    // `[1]` form — is the shipped-data shape of the accept above.
    #expect(try diagnostic(["phase_index": 1, "phase_type": "conditional"]) == nil)
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

  // MARK: - Remaining diagnostics
  //
  // Every `return` in `alignmentDiagnostic`, `phasePathSelfConsistency`,
  // `conditionalDiagnostic`, `conditionalAsLeafDiagnostic` and
  // `branchResolvedDiagnostic` needs a control, or the ones without are the
  // same unverified-guard defect these exist to prevent. All five, not the two
  // that existed when this was written — the extractions since then moved
  // exits out of the named pair, and the branch-arm controls now live in
  // `+Branch.swift`.

  @Test func emptyPhasePathIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [Int](), "phase_type": "vote"
    ])
    #expect(found?.contains("phase_path is empty") == true, "got: \(found ?? "nil")")
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
