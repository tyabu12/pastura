import Foundation
import Testing

@testable import Pastura

// Inline code-phase narration line (`ChatItem.codePhaseLine`) tests for
// `ReplayViewModel` (#932) — the demo mirror of the live sim's inline log
// entries (`SimulationView`'s `secondaryLogEntryView`). Before #932 these
// events were a silent no-op in `apply()`, so assign-based demos lost the
// per-round お題 that grounds every agent response.
//
// Sibling-file `extension` per `.claude/rules/testing.md` — NOT a new `@Suite`
// (a parallel suite would race the VM-spawning original on the shared test
// process; the `.serialized` / `.timeLimit` traits live on the base `@Suite`).
extension ReplayViewModelTests {

  // MARK: - Fixtures

  /// A turn preceded (by `phase_index`) by an `assign` code-phase event, so the
  /// お題 chronologically lands before the round's speak turn — exactly the
  /// real-data shape (assign is phase_index 0, speak is phase_index 1).
  static let assignmentThenTurnYAML = """
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
        summary: 'Alice assigned: topic X'
        payload:
          kind: assignment
          agent: Alice
          value: 'topic X'
    """

  /// A summarize code-phase event carrying narrator text in the top-level
  /// `summary` field (that field, NOT `payload`, is the source of `.summary`).
  static let summaryYAML = """
    schema_version: 1
    turns:
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hello' }
    code_phase_events:
      - round: 1
        phase_index: 1
        phase_type: summarize
        summary: 'the round wrapped up'
        payload:
          kind: summary
    """

  /// An `event_inject` code-phase event with a hit (non-nil `event`).
  static let eventInjectedYAML = """
    schema_version: 1
    turns:
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hello' }
    code_phase_events:
      - round: 1
        phase_index: 1
        phase_type: event_inject
        summary: 'a wild event appears'
        payload:
          kind: eventInjected
          event: 'a wild event appears'
    """

  /// All `CodePhaseLine`s currently in the VM's chat stream, in order.
  static func codePhaseLines(_ viewModel: ReplayViewModel) -> [ReplayViewModel.CodePhaseLine] {
    viewModel.chatItems.compactMap {
      if case .codePhaseLine(_, let line) = $0 { return line }
      return nil
    }
  }

  // MARK: - Inline append (the reported bug)

  /// The assignment お題 now renders as an inline `.codePhaseLine` — previously a
  /// silent no-op. This is the exact regression: reverting `apply()`'s
  /// `.assignment` arm to `return` makes this fail.
  @Test func assignmentEventAppendsInlineLine() async throws {
    let source = try YAMLReplaySource(
      yaml: Self.assignmentThenTurnYAML, scenario: Self.makeScenario(),
      config: Self.fastConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      !Self.codePhaseLines(viewModel).isEmpty
    }
    #expect(
      Self.codePhaseLines(viewModel).contains {
        if case .assignment(let agent, let value) = $0 {
          return agent == "Alice" && value == "topic X"
        }
        return false
      })
  }

  /// The お題 line lands BEFORE the round's agent turn — without it the response
  /// has no context (the whole point of the fix).
  @Test func assignmentLinePrecedesRoundTurns() async throws {
    let source = try YAMLReplaySource(
      yaml: Self.assignmentThenTurnYAML, scenario: Self.makeScenario(),
      config: Self.fastConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      !viewModel.agentOutputs.isEmpty && !Self.codePhaseLines(viewModel).isEmpty
    }
    let assignIndex = viewModel.chatItems.firstIndex {
      if case .codePhaseLine(_, .assignment) = $0 { return true }
      return false
    }
    let turnIndex = viewModel.chatItems.firstIndex {
      if case .agentOutput = $0 { return true }
      return false
    }
    guard let assignIndex, let turnIndex else {
      Issue.record("Missing assignment line or agent turn in \(viewModel.chatItems)")
      return
    }
    #expect(assignIndex < turnIndex)
  }

  @Test func summaryEventAppendsInlineLine() async throws {
    let source = try YAMLReplaySource(
      yaml: Self.summaryYAML, scenario: Self.makeScenario(), config: Self.fastConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      !Self.codePhaseLines(viewModel).isEmpty
    }
    #expect(
      Self.codePhaseLines(viewModel).contains {
        if case .summary(let text) = $0 { return text == "the round wrapped up" }
        return false
      })
  }

  @Test func eventInjectedAppendsInlineLine() async throws {
    let source = try YAMLReplaySource(
      yaml: Self.eventInjectedYAML, scenario: Self.makeScenario(),
      config: Self.fastConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.fastConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      !Self.codePhaseLines(viewModel).isEmpty
    }
    #expect(
      Self.codePhaseLines(viewModel).contains {
        if case .eventInjected(let event) = $0 { return event == "a wild event appears" }
        return false
      })
  }

  // MARK: - Dual surface (inline line AND closing-card accumulator, #868/#884)

  /// `.scoreUpdate` must BOTH append an inline line AND still feed the closing
  /// card — the two surfaces are independent, so restoring the inline line must
  /// not regress the ranking card.
  @Test func scoreUpdateAppendsLineAndStillFeedsClosingCard() async throws {
    let source = try Self.makeRankingSource(config: Self.holdConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.holdConfig, contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      Self.hasResultCard(viewModel)
    }
    // Inline line present …
    #expect(
      Self.codePhaseLines(viewModel).contains {
        if case .scoreUpdate(let scores) = $0 { return scores["Alice"] == 5 }
        return false
      })
    // … AND the closing card still resolved from the same accumulator.
    #expect(Self.hasResultCard(viewModel))
  }

  // MARK: - ContentFilter scope (defense-in-depth, header § "ContentFilter scope")

  /// The assignment `value` is filtered (LLM/authored text) but the `agent`
  /// name (structured identifier) passes through unchanged.
  @Test func filtersAssignmentValueNotAgentName() async throws {
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
          summary: 'Alice assigned: a secret topic'
          payload:
            kind: assignment
            agent: Alice
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
      case .assignment(let agent, let value)? = Self.codePhaseLines(viewModel).first(where: {
        if case .assignment = $0 { return true }
        return false
      })
    else {
      Issue.record("No assignment line in \(Self.codePhaseLines(viewModel))")
      return
    }
    #expect(agent == "Alice")  // structured identifier — unfiltered
    #expect(!value.contains("secret"))
    #expect(value.contains("XXX"))
  }

  // MARK: - Lifecycle chapter separators (#932 follow-up)

  /// `.roundStarted` appends an inline round separator carrying the round pair,
  /// mirroring the live sim's `roundSeparator`.
  @Test func roundStartedAppendsRoundSeparator() async throws {
    let viewModel = try Self.makeVM()  // threeTurnYAML: round 1 / total 1
    viewModel.start()
    await Self.waitForState(viewModel) { _ in
      viewModel.chatItems.contains {
        if case .roundSeparator = $0 { return true }
        return false
      }
    }
    #expect(
      viewModel.chatItems.contains {
        if case .roundSeparator(_, let round, let total) = $0 {
          return round == 1 && total == 1
        }
        return false
      })
  }

  /// `.phaseStarted` appends an inline phase separator carrying the phase type,
  /// mirroring the live sim's `phaseSeparator` / inline badge dispatch.
  @Test func phaseStartedAppendsPhaseSeparator() async throws {
    let viewModel = try Self.makeVM()  // threeTurnYAML: speak_all
    viewModel.start()
    await Self.waitForState(viewModel) { _ in
      viewModel.chatItems.contains {
        if case .phaseSeparator = $0 { return true }
        return false
      }
    }
    #expect(
      viewModel.chatItems.contains {
        if case .phaseSeparator(_, let phaseType) = $0 { return phaseType == .speakAll }
        return false
      })
  }

  /// Chapter order at a source head: round separator → phase separator → the
  /// round's first agent turn (no intro card here — the default fixture's
  /// `description` is empty).
  @Test func separatorsPrecedeFirstTurn() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in !viewModel.agentOutputs.isEmpty }
    let roundIndex = viewModel.chatItems.firstIndex {
      if case .roundSeparator = $0 { return true }
      return false
    }
    let phaseIndex = viewModel.chatItems.firstIndex {
      if case .phaseSeparator = $0 { return true }
      return false
    }
    let turnIndex = viewModel.chatItems.firstIndex {
      if case .agentOutput = $0 { return true }
      return false
    }
    guard let roundIndex, let phaseIndex, let turnIndex else {
      Issue.record("Missing a separator or turn in \(viewModel.chatItems)")
      return
    }
    #expect(roundIndex < phaseIndex)
    #expect(phaseIndex < turnIndex)
  }

  @Test func filtersSummaryText() async throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hello' }
      code_phase_events:
        - round: 1
          phase_index: 1
          phase_type: summarize
          summary: 'a secret recap'
          payload:
            kind: summary
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
      case .summary(let text)? = Self.codePhaseLines(viewModel).first(where: {
        if case .summary = $0 { return true }
        return false
      })
    else {
      Issue.record("No summary line in \(Self.codePhaseLines(viewModel))")
      return
    }
    #expect(!text.contains("secret"))
    #expect(text.contains("XXX"))
  }
}
