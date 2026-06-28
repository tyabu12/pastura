import Testing

@testable import Pastura

/// Reveal-position handoff (bug 2) contract: the pure seed-clamp +
/// reveal-target helpers, and the live-Sim committed/streaming call-site
/// signatures. Split from `AgentOutputRowContractTests` (same suite via
/// `extension`, NOT a new `@Suite` — see `.claude/rules/testing.md`).
///
/// The `@State`-seeded `visibleChars` itself can't be observed without a
/// SwiftUI host (per the parent suite's caveat); these pin the pure logic
/// that decides the seed and the call-site shapes that feed it.
extension AgentOutputRowContractTests {

  // MARK: - clampedInitialVisibleChars (seed clamp)

  @Test func clampedSeedWithinRangeIsUnchanged() {
    #expect(AgentOutputRow.clampedInitialVisibleChars(3, targetLength: 10) == 3)
    #expect(AgentOutputRow.clampedInitialVisibleChars(0, targetLength: 10) == 0)
    #expect(AgentOutputRow.clampedInitialVisibleChars(10, targetLength: 10) == 10)
  }

  @Test func clampedSeedAboveTargetClampsToTarget() {
    // A filter-shrunk committed primary can yield a seed past the row's
    // reveal length — clamp to fully-revealed, never overshoot the counter.
    #expect(AgentOutputRow.clampedInitialVisibleChars(99, targetLength: 5) == 5)
  }

  @Test func clampedSeedNegativeIsZero() {
    #expect(AgentOutputRow.clampedInitialVisibleChars(-4, targetLength: 10) == 0)
  }

  @Test func clampedSeedZeroTargetIsZero() {
    #expect(AgentOutputRow.clampedInitialVisibleChars(7, targetLength: 0) == 0)
    #expect(AgentOutputRow.clampedInitialVisibleChars(7, targetLength: -3) == 0)
  }

  // MARK: - revealTargetLength (pure form `targetLength` delegates to)

  @Test func revealTargetLengthMatchesInstanceTargetLength() {
    // The static helper and the instance property must agree — init uses the
    // static to size the seed clamp before `self` exists.
    let output = TurnOutput(fields: ["statement": "hello", "inner_thought": "musing"])
    let row = AgentOutputRow(
      agent: "Alice", output: output, phaseType: .speakAll, showAllThoughts: true)
    let viaStatic = AgentOutputRow.revealTargetLength(
      output: output, phaseType: .speakAll,
      streamingPrimary: nil, streamingThought: nil, showInnerThought: true)
    #expect(viaStatic == row.targetLength)
    #expect(viaStatic == "hello".count + "musing".count)
  }

  @Test func revealTargetLengthDecoratesVoteArrow() {
    // Vote primary counts the `→ ` affordance — the seed space must match
    // the committed row's decorated reveal length.
    let output = TurnOutput(fields: ["vote": "Dave"])
    #expect(
      AgentOutputRow.revealTargetLength(
        output: output, phaseType: .vote,
        streamingPrimary: nil, streamingThought: nil, showInnerThought: false)
        == "→ Dave".count)
  }

  // MARK: - Call-site signatures (live Sim committed / streaming rows)

  @Test func agentOutputRowAcceptsCommittedHandoffCallSite() {
    // Matches SimulationView.logEntryView's committed row: handoff seed +
    // growsWithReveal + isLatest-gated scroll-follow.
    _ = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hello"]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: true,
      charsPerSecond: 10,
      onRevealProgress: {},
      growsWithReveal: true,
      initialVisibleChars: 3,
      debugRowID: "entry"
    )
  }

  @Test func agentOutputRowAcceptsStreamingReportCallSite() {
    // Matches SimulationView streaming row: onStreamingRevealProgress wired
    // (count-bearing) alongside the count-free onRevealProgress scroll signal.
    _ = AgentOutputRow(
      agent: "Bob",
      output: TurnOutput(fields: [:]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: false,
      charsPerSecond: 10,
      onRevealProgress: {},
      onStreamingRevealProgress: { _ in },
      streamingPrimary: "partial",
      streamingThought: nil,
      growsWithReveal: true,
      debugRowID: "stream-Bob"
    )
  }
}
