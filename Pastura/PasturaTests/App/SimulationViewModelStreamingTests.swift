import Foundation
import Testing

@testable import Pastura

/// Event-handling tests for the streaming path
/// (``SimulationEvent/agentOutputStream(agent:primary:thought:)``).
/// Split from `SimulationViewModelTests.swift` to keep that suite under
/// its per-file lint budget.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct SimulationViewModelStreamingTests {

  // MARK: - Helpers

  // internal (not private) so sibling-file extensions
  // (SimulationViewModelStreamingTests+Focus) can call it — see testing.md.
  func makeSUT(
    contentFilter: ContentFilter = ContentFilter(blockedPatterns: [])
  ) throws -> (sut: SimulationViewModel, scenario: Scenario) {
    let db = try DatabaseManager.inMemory()
    let simRepo = GRDBSimulationRepository(dbWriter: db.dbWriter)
    let turnRepo = GRDBTurnRepository(dbWriter: db.dbWriter)
    let scenarioRepo = GRDBScenarioRepository(dbWriter: db.dbWriter)
    try scenarioRepo.save(
      ScenarioRecord(
        id: "test", name: "Test", yamlDefinition: "",
        isPreset: false, createdAt: Date(), updatedAt: Date()
      ))
    let scenario = makeTestScenario(agentNames: ["Alice", "Bob"], rounds: 3)
    let sut = SimulationViewModel(
      contentFilter: contentFilter,
      simulationRepository: simRepo,
      turnRepository: turnRepo
    )
    return (sut, scenario)
  }

  // MARK: - Tests

  @Test func agentOutputStreamWithNilPrimaryKeepsThinking() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.thinkingAgents.contains("Alice"))

    // Partial parser has not yet seen the opening quote — primary is nil.
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: nil, thought: nil),
      scenario: scenario)

    #expect(
      sut.thinkingAgents.contains("Alice"),
      "thinking indicator should stay until primary opens")
    #expect(sut.streamingSnapshot == nil)
  }

  @Test func agentOutputStreamWithPrimaryRemovesThinkingAndSetsSnapshot() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)

    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "", thought: nil),
      scenario: scenario)

    #expect(
      !sut.thinkingAgents.contains("Alice"),
      "thinking indicator should disappear once primary opens")
    #expect(sut.streamingSnapshot?.agent == "Alice")
    #expect(sut.streamingSnapshot?.primary == "")
    #expect(sut.streamingSnapshot?.phaseType == .speakAll)
  }

  // Regression: #132 landed the streaming path but bypassed ContentFilter
  // at snapshot construction — blocked patterns were visible during
  // streaming even though the committed AgentOutputRow filtered them.
  // App Store compliance requires displayed output to pass through the
  // filter, including the in-flight snapshot. Issue #133 PR#1.
  @Test func agentOutputStreamAppliesContentFilter() throws {
    let (sut, scenario) = try makeSUT(
      contentFilter: ContentFilter(blockedPatterns: ["fuck"], replacement: "***"))
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(
        agent: "Alice", primary: "what the fuck", thought: "fuck it"),
      scenario: scenario)

    #expect(sut.streamingSnapshot?.primary == "what the ***")
    #expect(sut.streamingSnapshot?.thought == "*** it")
  }

  // Guard against a future refactor that normalises `thought` to "" via
  // `thought ?? ""` before filtering — that would clobber the signal
  // `AgentOutputRow` uses to decide whether to render the inner-thought
  // reveal gate.
  @Test func agentOutputStreamPreservesNilThought() throws {
    let (sut, scenario) = try makeSUT(
      contentFilter: ContentFilter(blockedPatterns: ["fuck"], replacement: "***"))
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)

    #expect(sut.streamingSnapshot?.thought == nil)
  }

  @Test func agentOutputStreamProgressivelyUpdatesSnapshot() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)

    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hel", thought: nil),
      scenario: scenario)
    #expect(sut.streamingSnapshot?.primary == "hel")

    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: "secret"),
      scenario: scenario)
    #expect(sut.streamingSnapshot?.primary == "hello")
    #expect(sut.streamingSnapshot?.thought == "secret")
  }

  @Test func agentOutputFinalizationClearsSnapshot() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    #expect(sut.streamingSnapshot != nil)

    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    #expect(sut.streamingSnapshot == nil)
    #expect(
      sut.logEntries.contains { entry in
        if case .agentOutput(let agent, _, _) = entry.kind {
          return agent == "Alice"
        }
        return false
      })
  }

  @Test func inferenceStartedClearsStaleStreamingSnapshot() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "partial", thought: nil),
      scenario: scenario)
    #expect(sut.streamingSnapshot != nil)

    // A parse retry re-fires `inferenceStarted` — the stale partial
    // must not leak into the new attempt's UI.
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.streamingSnapshot == nil)
  }
}
