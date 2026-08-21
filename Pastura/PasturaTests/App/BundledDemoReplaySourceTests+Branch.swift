import Foundation
import Testing

@testable import Pastura

// Branch-resolution controls for
// ``BundledDemoReplaySourceTests/conditionalDiagnostic(entry:phaseTypeRaw:phase:phaseIndex:)``
// and its two extracted arms.
//
// Split from `+Alignment.swift`, which holds the fixture and the
// coordinate-shape controls, because that file reached SwiftLint's 400-line
// `file_length` cap — measured: a 502-line file under `Pastura/` reddens
// `swiftlint lint --strict`, both whole-tree and with the file as a positional
// argument. Two things DO suppress it, and both misled a measurement of this
// during review: a probe file placed outside `.swiftlint.yml`'s `included:`
// scope (path-independent rules still fire there, so the run looks live), and
// the parent file's own blanket `file_length` disable directive on its first
// line. (Named, not quoted: SwiftLint parses the directive's literal text
// wherever it appears, so writing it out here would switch the rule off for
// THIS file — a comment about a directive must not spell the directive.) The fixture and the `diagnostic(_:)` helper stay in `+Alignment.swift`
// and are reachable here only because this split widened them to internal —
// file scope does not reach an extension in another file, the same trap
// `.claude/rules/testing.md` § "Splitting a Suite Across Files" records for
// `private`. (An earlier draft of this header asserted they were already
// unscoped; they were not, and the build said so.)
//
// Extension + sibling file, NOT a new `@Suite`.
extension BundledDemoReplaySourceTests {

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

  @Test func wrongBranchIsCaught() throws {
    // The discriminating case for `branch:`. `[1, 0]` is `vote` in the then
    // branch and `summarize` in the else branch — identical path, so ONLY the
    // branch tells them apart. Without `branch:` this exact entry passes (the
    // test below pins that), which is what makes this a real control rather
    // than a restatement of the branch-blind indexed check.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "branch": "else", "phase_type": "vote"
    ])
    #expect(found?.contains("which is summarize") == true, "got: \(found ?? "nil")")
  }

  @Test func wrongBranchIsNotCaughtWithoutTheBranchField() throws {
    // Negative control for the control above: the same misalignment is INVISIBLE
    // when `branch:` is absent, because SOME branch holds `vote` at index 0 —
    // `then` does — and only `branch:` says which one ran. Pinning the gap
    // stops a later reader from over-trusting the branch-blind check. (Not the
    // union check: this path stopped using one when the indexed check landed.)
    #expect(
      try diagnostic([
        "phase_index": 1, "phase_path": [1, 0], "phase_type": "vote"
      ]) == nil)
  }

  @Test func branchOfWrongTypeIsCaught() throws {
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "branch": 0, "phase_type": "vote"
    ])
    #expect(found?.contains("not a String") == true, "got: \(found ?? "nil")")
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

  @Test func branchIndexOutOfRangeIsCaught() throws {
    // `then` holds two phases, so `then[3]` names nothing.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 3], "branch": "then", "phase_type": "vote"
    ])
    #expect(found?.contains("that branch holds 2 phase(s)") == true, "got: \(found ?? "nil")")
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

  @Test func typeAbsentFromTheIndexedSubPhaseIsCaught() throws {
    // Nested path, no `branch` — the exporter's shape. `[1, 0]` is `vote` in
    // then and `summarize` in else, so `speak_all` matches neither — even
    // though it IS in the union of both branches, as `then[1]`. That gap is
    // the whole difference between this check and
    // `typeAbsentFromBothBranchesIsCaughtInTheV1Shape` in `+Alignment.swift`,
    // which is where the union check still runs.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1, 0], "phase_type": "speak_all"
    ])
    #expect(
      found?.contains("across the branches") == true, "got: \(found ?? "nil")")
  }

  @Test func branchAlongsideTheConditionalItselfIsCaught() throws {
    // The exit that accepts `phase_type: conditional` returns early, so
    // everything below it is skipped — including the whole `branch:` arm. An
    // earlier revision placed it above that arm, which accepted all four
    // shapes below outright.
    for branch in ["then", "else", "maybe"] {
      let found = try diagnostic([
        "phase_index": 1, "phase_path": [1], "branch": branch,
        "phase_type": "conditional"
      ])
      #expect(
        found?.contains("but `branch:` claims") == true,
        "branch '\(branch)' — got: \(found ?? "nil")")
    }
  }

  @Test func nonStringBranchAlongsideTheConditionalItselfIsCaught() throws {
    // `branch: 0` is the shape that bypassed the presence-not-cast String
    // check, so it gets its own arm rather than riding the loop above.
    let found = try diagnostic([
      "phase_index": 1, "phase_path": [1], "branch": 0, "phase_type": "conditional"
    ])
    #expect(found?.contains("but `branch:` claims") == true, "got: \(found ?? "nil")")
  }

  @Test func branchOnANonConditionalPhaseIsCaught() throws {
    // Only a conditional has branches. Same fault class as the Critical one
    // level up: a field the coordinate cannot support, silently ignored.
    let found = try diagnostic([
      "phase_index": 0, "phase_path": [0], "branch": "then", "phase_type": "speak_all"
    ])
    #expect(found?.contains("which has no branches") == true, "got: \(found ?? "nil")")
  }
}
