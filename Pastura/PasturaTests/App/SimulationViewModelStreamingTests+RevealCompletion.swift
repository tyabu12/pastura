import Foundation
import Testing

@testable import Pastura

/// Latest-row reveal-completion latch tests (#934) — the ADR-017 Phase B adopt
/// path must NOT re-type the latest committed row when a parked run is
/// re-projected into a fresh `SimulationView`. Split from
/// `SimulationViewModelStreamingTests` to keep that suite under the
/// `type_body_length` / `file_length` caps. Same suite via `extension` — NOT
/// a new `@Suite` (Swift Testing runs suites in parallel; see
/// `.claude/rules/testing.md`).
///
/// The reveal-completion FIRING (the natural-vs-cancel distinction inside
/// `AgentOutputRow`'s animation `Task`) is animation-timing code and stays
/// device-QA / code-review-gated per view-testing.md rule 4; these tests pin
/// the pure VM decision logic that the firing drives.
extension SimulationViewModelStreamingTests {

  // MARK: - Reveal-completion latch (latest row static after it finished)

  @Test func latestRowIsStaticOnceRevealCompleted() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hello"]),
        phaseType: .speakAll),
      scenario: scenario)

    let id = try #require(sut.latestAgentOutputId)
    // Before completion the latest row still animates at cps.
    #expect(sut.effectiveCharsPerSecond(forEntryId: id) == PlaybackSpeed.normal.charsPerSecond)

    sut.markLatestRowRevealCompleted(entryId: id)
    // After completion it must render static so an adopt re-projection does not
    // re-type it.
    #expect(sut.effectiveCharsPerSecond(forEntryId: id) == nil)
  }

  @Test func markLatestRowRevealCompletedIgnoresStaleEntry() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hi"]),
        phaseType: .speakAll),
      scenario: scenario)
    let aliceId = try #require(sut.latestAgentOutputId)
    // A newer row commits — Alice is no longer the latest.
    sut.handleEvent(
      .agentOutput(
        agent: "Bob", output: TurnOutput(fields: ["statement": "yo"]),
        phaseType: .speakAll),
      scenario: scenario)
    let bobId = try #require(sut.latestAgentOutputId)

    // A stale completion for the no-longer-latest row is ignored.
    sut.markLatestRowRevealCompleted(entryId: aliceId)
    #expect(sut.effectiveCharsPerSecond(forEntryId: bobId) == PlaybackSpeed.normal.charsPerSecond)

    // The current latest row's completion does latch.
    sut.markLatestRowRevealCompleted(entryId: bobId)
    #expect(sut.effectiveCharsPerSecond(forEntryId: bobId) == nil)
  }

  @Test func newCommitResetsCompletionLatch() throws {
    let (sut, scenario) = try makeSUT()
    sut.speed = .normal
    sut.handleEvent(
      .phaseStarted(phaseType: .speakAll, phasePath: [0]), scenario: scenario)
    sut.handleEvent(
      .agentOutput(
        agent: "Alice", output: TurnOutput(fields: ["statement": "hi"]),
        phaseType: .speakAll),
      scenario: scenario)
    let aliceId = try #require(sut.latestAgentOutputId)
    sut.markLatestRowRevealCompleted(entryId: aliceId)
    #expect(sut.effectiveCharsPerSecond(forEntryId: aliceId) == nil)

    // A newer row commits — the latch resets so the fresh latest row animates.
    sut.handleEvent(
      .agentOutput(
        agent: "Bob", output: TurnOutput(fields: ["statement": "yo"]),
        phaseType: .speakAll),
      scenario: scenario)
    let bobId = try #require(sut.latestAgentOutputId)
    #expect(sut.effectiveCharsPerSecond(forEntryId: bobId) == PlaybackSpeed.normal.charsPerSecond)
  }
}
