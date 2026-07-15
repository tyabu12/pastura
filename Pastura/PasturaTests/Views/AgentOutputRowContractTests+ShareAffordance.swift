import Testing

@testable import Pastura

/// Per-row share affordance (#1080) gating: the glyph must appear only after
/// the row's typewriter has fully revealed (never mid-reveal). Split from
/// `AgentOutputRowContractTests` per `.claude/rules/testing.md`
/// § "Splitting a Suite Across Files" (same suite via `extension`, NOT a new
/// `@Suite`).
extension AgentOutputRowContractTests {

  @Test func revealSettledTruthTable() {
    // Not settled while the counter is still catching up to the target —
    // the share glyph stays hidden mid-reveal.
    #expect(AgentOutputRow.revealSettled(visibleChars: 0, targetLength: 10) == false)
    #expect(AgentOutputRow.revealSettled(visibleChars: 9, targetLength: 10) == false)
    // Settled once the counter reaches (or, defensively, passes) the target.
    #expect(AgentOutputRow.revealSettled(visibleChars: 10, targetLength: 10) == true)
    #expect(AgentOutputRow.revealSettled(visibleChars: 11, targetLength: 10) == true)
    // Empty row (target 0) is settled from the first render — the glyph is not
    // withheld on a zero-length bubble.
    #expect(AgentOutputRow.revealSettled(visibleChars: 0, targetLength: 0) == true)
  }

  @Test func shareAffordanceFadeDurationPinned() {
    // Change-detector on the share-glyph fade-in duration. Code-review-gated
    // timing token with no automated firing signal — a failure is NOT a bug, it
    // means the value drifted (likely in an unrelated refactor). Confirm the
    // change passed review, then update the expectation.
    #expect(AgentOutputRow.shareAffordanceFadeDuration == 0.35)
  }
}
