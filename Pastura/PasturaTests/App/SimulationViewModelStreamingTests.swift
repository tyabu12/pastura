import Foundation
import Testing

@testable import Pastura

/// Event-handling tests for the streaming path
/// (``SimulationEvent/agentOutputStream(agent:primary:thought:)``).
/// Split from `SimulationViewModelTests.swift` to keep that suite under
/// its per-file lint budget.
@MainActor
struct SimulationViewModelStreamingTests {

  // MARK: - Helpers

  private func makeSUT(
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
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
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

  @Test func agentOutputStreamProgressivelyUpdatesSnapshot() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)

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
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
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
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "partial", thought: nil),
      scenario: scenario)
    #expect(sut.streamingSnapshot != nil)

    // A parse retry re-fires `inferenceStarted` — the stale partial
    // must not leak into the new attempt's UI.
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.streamingSnapshot == nil)
  }

  // MARK: - Pre-reveal tracking (committed rows that streamed live)

  @Test func effectiveCpsIsNilForPrerevealedEntry() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal  // non-instant → helper fallback would otherwise be non-nil
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)

    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    let committedId = try #require(sut.latestAgentOutputId)
    #expect(sut.prerevealedAgentOutputIds.contains(committedId))
    #expect(sut.effectiveCharsPerSecond(forEntryId: committedId) == nil)
  }

  @Test func effectiveCpsFallsBackToSpeedForNonStreamedEntry() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
    // No .agentOutputStream — commit directly.
    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    let committedId = try #require(sut.latestAgentOutputId)
    #expect(!sut.prerevealedAgentOutputIds.contains(committedId))
    #expect(
      sut.effectiveCharsPerSecond(forEntryId: committedId) == PlaybackSpeed.normal.charsPerSecond)
  }

  @Test func agentOutputForDifferentAgentDoesNotMark() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
    // Snapshot is for Alice…
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    // …but the commit is for Bob. Snapshot.agent != agent → do not mark.
    let output = TurnOutput(fields: ["statement": "hi"])
    sut.handleEvent(
      .agentOutput(agent: "Bob", output: output, phaseType: .speakAll),
      scenario: scenario)

    let bobId = try #require(sut.latestAgentOutputId)
    #expect(!sut.prerevealedAgentOutputIds.contains(bobId))
    #expect(sut.effectiveCharsPerSecond(forEntryId: bobId) == PlaybackSpeed.normal.charsPerSecond)
  }

  @Test func parseRetryAfterStreamMarksOnlyRetryEntry() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
    // Attempt 1 — partial streams but never commits (parse fails).
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hel", thought: nil),
      scenario: scenario)
    // Retry clears the stale snapshot.
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.streamingSnapshot == nil)
    // Attempt 2 — partial streams and then commits.
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    // Exactly the retry's committed entry is marked; no orphan ids remain.
    let committedId = try #require(sut.latestAgentOutputId)
    #expect(sut.prerevealedAgentOutputIds == [committedId])
  }

  @Test func featureFlagOffLeavesSetEmpty() throws {
    let key = "realtimeStreamingEnabled"
    let original = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set(false, forKey: key)
    defer {
      if let original {
        UserDefaults.standard.set(original, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phaseIndex: 0), scenario: scenario)
    // Flag off → stream events no-op → snapshot stays nil.
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    #expect(sut.streamingSnapshot == nil)

    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    let committedId = try #require(sut.latestAgentOutputId)
    #expect(sut.prerevealedAgentOutputIds.isEmpty)
    #expect(
      sut.effectiveCharsPerSecond(forEntryId: committedId) == PlaybackSpeed.normal.charsPerSecond)
  }
}
