// Silently-inert configuration rules R7/R8/R9/R17 (ADR-024 D3). Extension of
// the existing suite (not a new @Suite) per .claude/rules/testing.md
// splitting pattern — reuses `linter` / `makeScenario` / `makeEventScenario`
// from the base file / the Ordering split.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  // MARK: - R7 choose-should-declare-options (warning)

  @Test func chooseWithoutOptionsFiresWarning() {
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [Phase(type: .choose)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "choose-should-declare-options")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func chooseWithEmptyOptionsListFiresWarning() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .choose, options: [])])
    #expect(linter.lint(scenario).contains { $0.ruleID == "choose-should-declare-options" })
  }

  @Test func chooseWithOptionsPasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .choose, options: ["cooperate", "betray"])])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R8 assign-source-nonempty (error)

  @Test func assignRandomOneWithEmptyArrayOfDictionariesFiresError() {
    let scenario = makeEventScenario(
      phases: [Phase(type: .assign, source: "events", target: .randomOne)],
      events: .arrayOfDictionaries([]))
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "assign-source-nonempty")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func assignRandomOneWithNonEmptyArrayOfDictionariesPasses() {
    let scenario = makeEventScenario(
      phases: [Phase(type: .assign, source: "events", target: .randomOne)],
      events: .arrayOfDictionaries([["majority": "a", "minority": "b"]]))
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func assignAllWithEmptyArrayFiresError() {
    let scenario = makeEventScenario(
      phases: [Phase(type: .assign, source: "events", target: .all)],
      events: .array([]))
    #expect(linter.lint(scenario).contains { $0.ruleID == "assign-source-nonempty" })
  }

  @Test func assignAllWithNonEmptyArrayPasses() {
    let scenario = makeEventScenario(
      phases: [Phase(type: .assign, source: "events", target: .all)],
      events: .array(["one", "two"]))
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func assignAllWithStringSourcePasses() {
    // A single-string source is a legitimate `.all` shape (never "empty" in
    // the nothing-to-iterate sense) — must NOT trip, per ADR-024's
    // Rule-precision notes.
    let scenario = makeEventScenario(
      phases: [Phase(type: .assign, source: "events", target: .all)],
      events: .string("the one topic"))
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func assignDefaultTargetIsAllForEmptyArray() {
    // `target` omitted defaults to `.all` (per `Phase`'s doc comment).
    let scenario = makeEventScenario(
      phases: [Phase(type: .assign, source: "events")],
      events: .array([]))
    #expect(linter.lint(scenario).contains { $0.ruleID == "assign-source-nonempty" })
  }

  // MARK: - R9 summarize-pairing-placeholders (warning)

  @Test func summarizeWithPairingPlaceholderWithoutRoundRobinChooseFiresWarning() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .summarize, template: "{agent1} chose {action1}")])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "summarize-pairing-placeholders")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func summarizeWithPairingPlaceholderAfterRoundRobinChoosePasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .choose, options: ["cooperate", "betray"], pairing: .roundRobin),
        Phase(type: .summarize, template: "{agent1} chose {action1}")
      ])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func summarizeWithoutPairingPlaceholdersPasses() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .summarize, template: "Round complete.")])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - R17 log-window-below-agent-count (warning)

  @Test func logWindowBelowAgentCountWithSpeakEachFiresWarning() {
    let scenario = makeLogWindowScenario(
      agents: 3, logWindow: 2, phases: [Phase(type: .speakEach)])
    let findings = linter.lint(scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "log-window-below-agent-count")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == nil)
  }

  @Test func logWindowAtOrAboveAgentCountPasses() {
    let scenario = makeLogWindowScenario(
      agents: 3, logWindow: 3, phases: [Phase(type: .speakEach)])
    #expect(linter.lint(scenario).isEmpty)
  }

  @Test func logWindowBelowAgentCountWithoutSpeakEachPasses() {
    let scenario = makeLogWindowScenario(
      agents: 3, logWindow: 2, phases: [Phase(type: .speakAll)])
    #expect(linter.lint(scenario).isEmpty)
  }

  // MARK: - Helper

  // Internal factory for scenarios needing `logWindow` (R17); the base
  // `makeScenario` doesn't take it.
  func makeLogWindowScenario(agents: Int, logWindow: Int, phases: [Phase]) -> Scenario {
    Scenario(
      id: "test", name: "Test", description: "Test",
      language: "ja",
      agentCount: agents, rounds: 1, context: "Context",
      personas: (0..<agents).map { Persona(name: "A\($0)", description: "D") },
      phases: phases,
      logWindow: logWindow
    )
  }
}
