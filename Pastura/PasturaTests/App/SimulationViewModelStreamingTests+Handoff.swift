import Foundation
import Testing

@testable import Pastura

/// Reveal-position handoff + typing-synced hold tests (bug 2), split from
/// `SimulationViewModelStreamingTests` to keep that suite under the
/// `type_body_length` / `file_length` caps. Same suite via `extension` — NOT
/// a new `@Suite` (Swift Testing runs suites in parallel; see
/// `.claude/rules/testing.md`).
extension SimulationViewModelStreamingTests {

  // MARK: - Reveal-position handoff (committed rows that streamed live)

  @Test func streamedEntryRecordsReportedHandoffSeed() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    // The live streaming row reports its reveal position before commit.
    sut.reportStreamingReveal(3)

    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    let committedId = try #require(sut.latestAgentOutputId)
    // Seeded at the reported position so the row continues typing from 3 —
    // it is NOT snapped (effectiveCharsPerSecond stays non-nil).
    #expect(sut.handoffSeed(forEntryId: committedId) == 3)
    #expect(
      sut.effectiveCharsPerSecond(forEntryId: committedId)
        == PlaybackSpeed.normal.charsPerSecond)
  }

  @Test func nonStreamedEntryHasZeroHandoffSeed() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    // No .agentOutputStream — commit directly.
    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    let committedId = try #require(sut.latestAgentOutputId)
    #expect(sut.handoffSeed(forEntryId: committedId) == 0)
    #expect(
      sut.effectiveCharsPerSecond(forEntryId: committedId)
        == PlaybackSpeed.normal.charsPerSecond)
  }

  @Test func differentAgentCommitGetsZeroHandoff() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    // Snapshot is for Alice (with a reported reveal)…
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    sut.reportStreamingReveal(4)
    // …but the commit is for Bob. snapshot.agent != agent → not streamed.
    let output = TurnOutput(fields: ["statement": "hi"])
    sut.handleEvent(
      .agentOutput(agent: "Bob", output: output, phaseType: .speakAll),
      scenario: scenario)

    let bobId = try #require(sut.latestAgentOutputId)
    #expect(sut.handoffSeed(forEntryId: bobId) == 0)
    #expect(
      sut.effectiveCharsPerSecond(forEntryId: bobId)
        == PlaybackSpeed.normal.charsPerSecond)
  }

  @Test func parseRetryAfterStreamSeedsOnlyRetryEntry() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    // Attempt 1 — partial streams and reports, but never commits (parse fails).
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hel", thought: nil),
      scenario: scenario)
    sut.reportStreamingReveal(2)
    // Retry clears the stale snapshot AND resets the reveal counter.
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.streamingSnapshot == nil)
    // Attempt 2 — partial streams, reports a fresh position, then commits.
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    sut.reportStreamingReveal(5)
    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    // Exactly the retry's committed entry is seeded; attempt 1's reported
    // position (2) did not leak — the seed is the retry's reported 5.
    let committedId = try #require(sut.latestAgentOutputId)
    #expect(sut.streamingHandoffChars.keys.count == 1)
    #expect(sut.handoffSeed(forEntryId: committedId) == 5)
  }

  @Test func reportedRevealDoesNotCarryToNextAgent() throws {
    // Critic Axis 4 (stale carryover): agent A's reported reveal must not seed
    // agent B's committed row when B's own streaming row never ticks. Fails if
    // either reset (inferenceStarted / commit boundary) is removed.
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    // A streams, reports a position, and commits.
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)
    sut.reportStreamingReveal(4)
    sut.handleEvent(
      .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hello"]),
        phaseType: .speakAll),
      scenario: scenario)
    // B starts and streams (so wasStreamed is true) but never reports.
    sut.handleEvent(.inferenceStarted(agent: "Bob"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Bob", primary: "hi", thought: nil),
      scenario: scenario)
    sut.handleEvent(
      .agentOutput(
        agent: "Bob", output: TurnOutput(fields: ["statement": "hi"]),
        phaseType: .speakAll),
      scenario: scenario)

    let bobId = try #require(sut.latestAgentOutputId)
    // Bob streamed (a handoff entry exists) but its seed is 0, NOT Alice's 4.
    #expect(sut.handoffSeed(forEntryId: bobId) == 0)
  }

  @Test func featureFlagOffLeavesHandoffEmpty() throws {
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
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
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
    #expect(sut.handoffSeed(forEntryId: committedId) == 0)
    #expect(
      sut.effectiveCharsPerSecond(forEntryId: committedId)
        == PlaybackSpeed.normal.charsPerSecond)
  }

  /// `.instant` speed must bypass the streaming snapshot gate entirely.
  /// Issue #133 PR#6; ADR-002 §11.2 Axis ③ (Choice 2 — event-layer).
  @Test func instantSpeedSkipsStreamingAndPreservesThinkingIndicator() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .instant
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    #expect(sut.thinkingAgents.contains("Alice"))

    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello", thought: nil),
      scenario: scenario)

    // Gate: snapshot must stay nil; thinking indicator must persist until commit.
    #expect(sut.streamingSnapshot == nil)
    #expect(sut.thinkingAgents.contains("Alice"))

    let output = TurnOutput(fields: ["statement": "hello"])
    sut.handleEvent(
      .agentOutput(agent: "Alice", output: output, phaseType: .speakAll),
      scenario: scenario)

    let committedId = try #require(sut.latestAgentOutputId)
    // No streaming row was ever set, so there is no handoff seed.
    #expect(sut.handoffSeed(forEntryId: committedId) == 0)
    // `.instant.charsPerSecond` is nil by definition; pins the instant-snap
    // invariant (the only case where the committed row still snaps to full).
    #expect(sut.effectiveCharsPerSecond(forEntryId: committedId) == nil)
  }

  // MARK: - Typing-synced hold (next turn waits for the reveal to finish)

  @Test func pendingTypingHoldReflectsRemainingTypingFromSeed() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(.inferenceStarted(agent: "Alice"), scenario: scenario)
    sut.handleEvent(
      .agentOutputStream(agent: "Alice", primary: "hello world", thought: nil),
      scenario: scenario)
    sut.reportStreamingReveal(6)  // "hello " already revealed
    sut.handleEvent(
      .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hello world"]),
        phaseType: .speakAll),
      scenario: scenario)

    let cps = try #require(PlaybackSpeed.normal.charsPerSecond)
    let expected = remainingTypingDurationMs(
      seed: 6, primary: "hello world", thought: "", charsPerSecond: cps)
    #expect(expected > 0)  // sanity: there is unrevealed tail to type
    #expect(sut.pendingTypingHold == .milliseconds(expected))
  }

  @Test func pendingTypingHoldIsZeroForInstant() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .instant
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hello"]),
        phaseType: .speakAll),
      scenario: scenario)
    #expect(sut.pendingTypingHold == .zero)
  }
}
