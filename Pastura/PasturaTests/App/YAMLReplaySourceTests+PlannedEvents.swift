import Foundation
import Testing

@testable import Pastura

// Tests for ``YAMLReplaySource.plannedEvents()`` — the VM-driven-pacing API
// introduced in Issue #169 (C-track PR1) alongside synthesised
// `.roundStarted` / `.phaseStarted` lifecycle events.
//
// Split from `YAMLReplaySourceTests.swift` to stay under the 400-line
// `file_length` cap. Extension + sibling-file pattern — NOT a new
// `@Suite` — because a second suite would race against the original on
// shared state (see `.claude/rules/testing.md`).
extension YAMLReplaySourceTests {

  // MARK: - Multi-round / multi-phase fixture

  /// 2-round, 2-phase scenario: `speak_all` (LLM phase) then `score_calc`
  /// (code phase). Used for lifecycle synthesis + chronological merge
  /// assertions.
  fileprivate static let twoRoundScenarioYAML = """
    id: ts2
    name: Test2
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
      - type: score_calc
        rule: constant
        value: 1
    """

  fileprivate func makeTwoRoundScenario() throws -> Scenario {
    try ScenarioLoader().load(yaml: Self.twoRoundScenarioYAML)
  }

  // MARK: - plannedEvents() — basic shape

  @Test func plannedEventsReturnsTurnAndCodePhaseKinds() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
      code_phase_events:
        - round: 1
          phase_index: 1
          phase_type: score_calc
          summary: 'tick'
          payload:
            kind: scoreUpdate
            scores: { Alice: 1 }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeTwoRoundScenario(), config: fastConfig)

    let paced = source.plannedEvents()

    // Expected chronological order with lifecycle synthesis:
    //   [roundStarted(1), phaseStarted(speak_all, [0]), agentOutput(Alice),
    //    phaseStarted(score_calc, [1]), scoreUpdate]
    #expect(paced.count == 5)
    #expect(paced[0].kind == .lifecycle)
    #expect(paced[1].kind == .lifecycle)
    #expect(paced[2].kind == .turn)
    #expect(paced[3].kind == .lifecycle)
    #expect(paced[4].kind == .codePhase)
  }

  // MARK: - Lifecycle synthesis: .roundStarted

  @Test func plannedEventsSynthesizesRoundStartedOnFirstEvent() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    let paced = source.plannedEvents()

    #expect(paced.count >= 1)
    if case .roundStarted(let round, let total) = paced[0].event {
      #expect(round == 1)
      // `totalRounds` comes from `scenario.rounds`, not the YAML — the
      // YAML has no `total_rounds` field.
      #expect(total == 1)
      #expect(paced[0].kind == .lifecycle)
    } else {
      Issue.record("Expected first event to be synthesised .roundStarted, got \(paced[0].event)")
    }
  }

  @Test func plannedEventsSynthesizesRoundStartedOnRoundTransition() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'r1' }
        - round: 2
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'r2' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeTwoRoundScenario(), config: fastConfig)

    let paced = source.plannedEvents()

    // Expected:
    //   [roundStarted(1,2), phaseStarted(speak_all,[0]), agentOutput(r1),
    //    roundStarted(2,2), phaseStarted(speak_all,[0]), agentOutput(r2)]
    #expect(paced.count == 6)
    if case .roundStarted(let round, _) = paced[3].event {
      #expect(round == 2)
      #expect(paced[3].kind == .lifecycle)
    } else {
      Issue.record("Expected .roundStarted(2) at index 3, got \(paced[3].event)")
    }
  }

  // MARK: - Lifecycle synthesis: .phaseStarted

  @Test func plannedEventsSynthesizesPhaseStartedOnPhaseTransition() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
      code_phase_events:
        - round: 1
          phase_index: 1
          phase_type: score_calc
          summary: 'tick'
          payload:
            kind: scoreUpdate
            scores: { Alice: 1 }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeTwoRoundScenario(), config: fastConfig)

    let paced = source.plannedEvents()

    // phaseStarted(speak_all, [0]) precedes the agentOutput;
    // phaseStarted(score_calc, [1]) precedes the scoreUpdate.
    if case .phaseStarted(let phaseType, let path) = paced[1].event {
      #expect(phaseType == .speakAll)
      #expect(path == [0])
      #expect(paced[1].kind == .lifecycle)
    } else {
      Issue.record("Expected .phaseStarted(speakAll,[0]) at index 1, got \(paced[1].event)")
    }
    if case .phaseStarted(let phaseType, let path) = paced[3].event {
      #expect(phaseType == .scoreCalc)
      #expect(path == [1])
      #expect(paced[3].kind == .lifecycle)
    } else {
      Issue.record("Expected .phaseStarted(scoreCalc,[1]) at index 3, got \(paced[3].event)")
    }
  }

  // MARK: - Explicit exclusions (do NOT synthesise)

  @Test func plannedEventsDoesNotSynthesizeRoundCompleted() throws {
    // Two rounds → if `.roundCompleted` were synthesised we'd see one
    // after each round's last event. The YAML schema has no slot for
    // per-round `scores` snapshots (spec §3.2), so synthesising it from
    // thin air would require heuristic score-accumulation which is worse
    // than absence.
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'r1' }
        - round: 2
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'r2' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeTwoRoundScenario(), config: fastConfig)

    for paced in source.plannedEvents() {
      if case .roundCompleted = paced.event {
        Issue.record(
          "plannedEvents() must NOT synthesise .roundCompleted (no per-round score slot in schema §3.2). Got \(paced.event)"
        )
      }
    }
  }

  @Test func plannedEventsDoesNotSynthesizeSimulationCompleted() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    for paced in source.plannedEvents() {
      if case .simulationCompleted = paced.event {
        Issue.record(
          "plannedEvents() must NOT synthesise .simulationCompleted (array-end signals completion)."
        )
      }
    }
  }

  // MARK: - Memoisation invariant

  @Test func plannedEventsIsStableAcrossCalls() throws {
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'yo' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    let first = source.plannedEvents()
    let second = source.plannedEvents()

    // Stability is load-bearing: `ReplayViewModel.State.paused` stores an
    // `eventCursor` index into this array; two calls must produce an
    // identical indexing or resume-from-position breaks silently.
    #expect(first == second)
  }

  // MARK: - Chronological merge

  @Test func plannedEventsMergesTurnsAndCodeEventsChronologically() throws {
    // Intentionally orders YAML sections NON-chronologically: round 2
    // turns come before round 1's code event in the document, but the
    // planner must merge them by (round, phase_index).
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'r1' }
        - round: 2
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'r2' }
      code_phase_events:
        - round: 1
          phase_index: 1
          phase_type: score_calc
          summary: 'r1 score'
          payload:
            kind: scoreUpdate
            scores: { Alice: 1 }
        - round: 2
          phase_index: 1
          phase_type: score_calc
          summary: 'r2 score'
          payload:
            kind: scoreUpdate
            scores: { Alice: 2 }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeTwoRoundScenario(), config: fastConfig)

    let paced = source.plannedEvents()

    // Expected chronological sequence:
    //   round 1: roundStarted(1), phaseStarted(speak_all,[0]),
    //            agentOutput(r1), phaseStarted(score_calc,[1]),
    //            scoreUpdate(r1)
    //   round 2: roundStarted(2), phaseStarted(speak_all,[0]),
    //            agentOutput(r2), phaseStarted(score_calc,[1]),
    //            scoreUpdate(r2)
    #expect(paced.count == 10)

    // Verify round 1's scoreUpdate comes BEFORE round 2's agentOutput.
    var sawR1Score = false
    var sawR2Turn = false
    for paced in paced {
      if case .scoreUpdate(let scores) = paced.event, scores["Alice"] == 1 {
        sawR1Score = true
      }
      if case .agentOutput(_, let output, _) = paced.event,
        output.statement == "r2" {
        #expect(sawR1Score, "r1 scoreUpdate must come before r2 agentOutput")
        sawR2Turn = true
      }
    }
    #expect(sawR2Turn)
  }

  // MARK: - events() backward compatibility

  @Test func eventsStreamDoesNotEmitLifecycleEvents() async throws {
    // The existing streaming `events()` API must keep its E1 contract:
    // only the user-recorded events in their declared order, no
    // synthesised lifecycle markers. `plannedEvents()` is the API for
    // lifecycle-aware consumers.
    let yaml = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'hi' }
      """
    let source = try YAMLReplaySource(
      yaml: yaml, scenario: makeScenario(), config: fastConfig)

    var collected: [SimulationEvent] = []
    for await event in source.events() { collected.append(event) }

    #expect(collected.count == 1)
    if case .agentOutput = collected[0] {
      // expected
    } else {
      Issue.record("Expected .agentOutput from events(), got \(collected[0])")
    }
  }
}
