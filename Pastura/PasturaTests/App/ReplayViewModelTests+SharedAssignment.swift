import Foundation
import Testing

@testable import Pastura

// Inline shared-assignment line (`ChatItem.codePhaseLine` → `.sharedAssignment`)
// tests for `ReplayViewModel` (#939) — the demo mirror of the live sim's shared
// お題 log entry. The round's shared topic (`assign` target: all) renders as one
// line with no agent attribution, distinct from the per-agent `.assignment`
// (word wolf) covered in `+CodePhaseLines`.
//
// Sibling-file `extension` per `.claude/rules/testing.md` — NOT a new `@Suite`
// (a parallel suite would race the VM-spawning original; the `.serialized` /
// `.timeLimit` traits live on the base `@Suite`). Split from `+CodePhaseLines`
// to keep that file under swiftlint's 400-line `file_length` cap.
extension ReplayViewModelTests {

  /// A turn preceded (by `phase_index`) by a `sharedAssignment` code-phase
  /// event (`assign` target: all, #939) — the round's shared お題 with no agent
  /// attribution, landing before the round's speak turn.
  static let sharedAssignmentThenTurnYAML = """
    schema_version: 1
    turns:
      - round: 1
        phase_index: 1
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hello' }
    code_phase_events:
      - round: 1
        phase_index: 0
        phase_type: assign
        summary: 'topic X'
        payload:
          kind: sharedAssignment
          value: 'topic X'
    """

  /// The shared お題 renders as an inline `.sharedAssignment` line (#939) —
  /// reverting `apply()`'s `.sharedAssignment` arm makes this fail.
  @Test func sharedAssignmentEventAppendsInlineLine() async throws {
    let source = try YAMLReplaySource(
      yaml: Self.sharedAssignmentThenTurnYAML, scenario: Self.makeScenario(),
      config: Self.fastConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      !Self.codePhaseLines(viewModel).isEmpty
    }
    #expect(
      Self.codePhaseLines(viewModel).contains {
        if case .sharedAssignment(let value) = $0 { return value == "topic X" }
        return false
      })
  }

  /// The shared お題 `value` is filtered (authored/LLM text), mirroring the
  /// per-agent assignment filtering.
  @Test func filtersSharedAssignmentValue() async throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 1
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hello' }
      code_phase_events:
        - round: 1
          phase_index: 0
          phase_type: assign
          summary: 'a secret topic'
          payload:
            kind: sharedAssignment
            value: 'a secret topic'
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: Self.makeScenario(), config: Self.fastConfig)
    let filter = ContentFilter(blockedPatterns: ["secret"], replacement: "XXX")
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: filter)
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      !Self.codePhaseLines(viewModel).isEmpty
    }
    guard
      case .sharedAssignment(let value)? = Self.codePhaseLines(viewModel).first(where: {
        if case .sharedAssignment = $0 { return true }
        return false
      })
    else {
      Issue.record("No shared-assignment line in \(Self.codePhaseLines(viewModel))")
      return
    }
    #expect(!value.contains("secret"))
    #expect(value.contains("XXX"))
  }
}
