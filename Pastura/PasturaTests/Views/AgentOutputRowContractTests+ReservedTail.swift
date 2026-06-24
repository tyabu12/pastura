import Testing

@testable import Pastura

// Sibling extension of `AgentOutputRowContractTests` per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files" — keeps the
// original file under swiftlint's 400-line `file_length` cap. Inherits the
// parent suite's `@MainActor` + `@Suite(.timeLimit(.minutes(1)))` traits (DO
// NOT add a new `@Suite` here — sibling suites race on shared state).
//
// ## shouldReserveHiddenTail (#785 growing-bubble opt-in)
//
// `shouldReserveHiddenTail` gates whether `primaryView` / `thoughtBody` keep
// the hidden `.clear` concat tail (reflow-stable, full layout from frame
// one) or drop it so the bubble grows with the visible prefix. The DL-time
// demo host opts in via `growsWithReveal: true`; everyone else keeps the
// default. The property folds in `shouldAnimate`, so the grow path is active
// ONLY on an animating replay row (latest + cps, no streaming override).
extension AgentOutputRowContractTests {

  @Test func reservesHiddenTailByDefaultEvenWhenAnimating() {
    // Default `growsWithReveal == false` → always reserve, regardless of
    // animation state. This is the Sim / Results / past-log invariant.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hi"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: 60
    )
    #expect(row.shouldReserveHiddenTail)
  }

  @Test func dropsHiddenTailForAnimatingDemoLatestRow() {
    // Demo opt-in on the latest animating row (no streaming override) →
    // drop the tail so the bubble grows.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hello there"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: 30,
      growsWithReveal: true
    )
    #expect(!row.shouldReserveHiddenTail)
  }

  @Test func reservesHiddenTailForOlderDemoRow() {
    // Demo opt-in but NOT the latest row → `shouldAnimate` false → reserve.
    // Older rows snap `visibleChars` to full, so the tail is empty anyway;
    // the guard makes the no-growth intent explicit.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hello there"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: false,
      charsPerSecond: 30,
      growsWithReveal: true
    )
    #expect(row.shouldReserveHiddenTail)
  }

  @Test func reservesHiddenTailForInstantDemoPlayback() {
    // `.instant` playback → `charsPerSecond == nil` → `shouldAnimate` false
    // → reserve (snap to full, no growth). Acceptance: "no breakage on
    // `.instant`" holds by construction.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hello there"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: nil,
      growsWithReveal: true
    )
    #expect(row.shouldReserveHiddenTail)
  }

  @Test func reservesHiddenTailWhenStreamingOverridePresent() {
    // Streaming path (`streamingPrimary != nil`) keeps the concat trick even
    // with the flag — the grow path is replay-only. Defensive: the demo host
    // never sets a streaming override, but a future caller might combine them.
    let row = AgentOutputRow(
      agent: "Bob",
      output: TurnOutput(fields: [:]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: false,
      charsPerSecond: 45,
      streamingPrimary: "partial",
      growsWithReveal: true
    )
    #expect(row.shouldReserveHiddenTail)
  }

  @Test func simAndResultsCallSitesReserveHiddenTail() {
    // Guard: the production Sim log-row and Results turn-row call sites do
    // NOT pass `growsWithReveal`, so they keep reflow-stable rendering. A
    // future refactor that flips the flag on Sim would regress this (grow
    // without Sim's scroll-follow). Mirrors the verbatim call sites pinned
    // in the parent file's "Public initializer signatures" section.
    let simLogRow = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hi"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: 60,
      onAnimatingChange: { _ in },
      debugRowID: "row-1"
    )
    let resultsRow = AgentOutputRow(
      agent: "Carol",
      output: TurnOutput(fields: ["vote": "Dave", "reason": "散歩"]),
      phaseType: .vote,
      showAllThoughts: true
    )
    #expect(simLogRow.shouldReserveHiddenTail)
    #expect(resultsRow.shouldReserveHiddenTail)
  }
}
