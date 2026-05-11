import Testing

@testable import Pastura

// Sibling extension of `AgentOutputRowContractTests` per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files" — the
// original file crossed swiftlint's 400-line `file_length` cap after the
// `shouldRevealThoughtSection` gate landed. Inherits the parent suite's
// `@MainActor` + `@Suite(.timeLimit(.minutes(1)))` traits (DO NOT add a
// new `@Suite` here — sibling suites race on shared state).
//
// ## Gate behavior
//
// Sim's live-streaming path naturally suppresses the `▸ THINKING` chevron
// until primary is fully revealed: `streamingThought` is empty until the
// LLM emits the `inner_thought` key, so `resolvedThought.isEmpty` short-
// circuits `thoughtSection`. Replay paths (DL Demo, Results, past logs)
// get `resolvedThought` from `output.innerThought` (a fully-known string)
// and used to render the chevron from frame 1 — visibly inconsistent with
// Sim. `shouldRevealThoughtSection(visibleChars:)` introduces a counter-
// driven gate so all *animating* call sites share the same two-phase
// reveal: primary first, then chevron + thought body. Non-animating rows
// short-circuit to `true` so the `.onAppear`-driven snap doesn't produce
// a one-frame chevron flicker on row mount.
extension AgentOutputRowContractTests {

  @Test func shouldRevealThoughtSectionFalseBeforePrimaryFullyRevealed() {
    // Animating row (`isLatest: true` + `charsPerSecond: 60`) — gate must
    // hide the chevron while the reveal counter is still below primary
    // length. This is the core regression guard for the Demo / Sim
    // streaming-latest behavior.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hello",  // 5 chars
        "inner_thought": "quiet"
      ]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: true,
      charsPerSecond: 60
    )
    #expect(row.shouldRevealThoughtSection(visibleChars: 0) == false)
    #expect(row.shouldRevealThoughtSection(visibleChars: 4) == false)
  }

  @Test func shouldRevealThoughtSectionTrueWhenPrimaryFullyRevealed() {
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hello",  // 5 chars
        "inner_thought": "quiet"
      ]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: true,
      charsPerSecond: 60
    )
    #expect(row.shouldRevealThoughtSection(visibleChars: 5) == true)
    #expect(row.shouldRevealThoughtSection(visibleChars: 10) == true)
  }

  @Test func shouldRevealThoughtSectionFalseWhenThoughtAbsent() {
    // Even with primary fully revealed, no thought → no section. Prevents
    // an empty chevron from appearing on phases / outputs that omit
    // `inner_thought`. Animating or not, the `resolvedThought.isEmpty`
    // guard short-circuits first.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hello"]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: true,
      charsPerSecond: 60
    )
    #expect(row.shouldRevealThoughtSection(visibleChars: 5) == false)
    #expect(row.shouldRevealThoughtSection(visibleChars: 100) == false)
  }

  @Test func shouldRevealThoughtSectionUsesStreamingPrimaryLength() {
    // Streaming row: the gate must compare against the live primary
    // buffer length, not the parsed-field length, so the chevron pops in
    // when the streaming buffer is fully revealed — even if the eventual
    // committed primary is longer or shorter. `streamingPrimary != nil`
    // also makes the row animating, so the counter-driven branch fires.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [:]),
      phaseType: .speakAll,
      showAllThoughts: true,
      charsPerSecond: 60,
      streamingPrimary: "live",  // 4 chars
      streamingThought: "thinking"
    )
    #expect(row.shouldRevealThoughtSection(visibleChars: 3) == false)
    #expect(row.shouldRevealThoughtSection(visibleChars: 4) == true)
  }

  /// Mirrors ``targetLengthPrefersStreamingPrimaryOverParsedPrimary``. Pins
  /// that `shouldRevealThoughtSection` reads `primaryText` (which short-
  /// circuits to `streamingPrimary`) rather than `output.primaryText(for:)`
  /// directly. A future refactor that drops the short-circuit would
  /// otherwise silently revert the streaming gate to the parsed-field
  /// length and re-introduce premature chevron pop-in during live
  /// inference.
  @Test func shouldRevealThoughtSectionUsesStreamingPrimaryLengthOverParsedPrimary() {
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "FINAL TEN"]),  // 9 chars
      phaseType: .speakAll,
      showAllThoughts: true,
      charsPerSecond: 60,
      streamingPrimary: "live",  // 4 chars — must win
      streamingThought: "thinking"
    )
    // visibleChars=4 fully reveals the live buffer (4 chars), so the gate
    // must flip true. If the gate read parsed-primary (9 chars), this
    // would still be false.
    #expect(row.shouldRevealThoughtSection(visibleChars: 4) == true)
  }

  @Test func shouldRevealThoughtSectionTrueImmediatelyForNonAnimatingRows() {
    // Non-animating row (default `isLatest: false`, no `charsPerSecond`,
    // no streaming override) → `shouldAnimate == false` → gate
    // short-circuits to `true` regardless of `visibleChars`. This
    // matches pre-fix replay behavior (chevron from frame 1) and
    // avoids the one-frame mount flicker that the `.onAppear`-driven
    // `visibleChars` snap would otherwise produce. Covers the
    // `ResultDetailView` turnRow path and the older non-latest rows in
    // SimulationView / ModelDownloadHostView.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [
        "statement": "hello",
        "inner_thought": "quiet"
      ]),
      phaseType: .speakAll,
      showAllThoughts: true
    )
    #expect(row.shouldRevealThoughtSection(visibleChars: 0) == true)
    #expect(row.shouldRevealThoughtSection(visibleChars: 100) == true)
  }

  @Test func shouldRevealThoughtSectionTrueWhenPrimaryNilOnAnimatingRow() {
    // Edge: an animating row with no primary text (rare — fall-through
    // path for outputs lacking the canonical phase field).
    // `primaryText?.count ?? 0 == 0` → gate satisfied at visibleChars=0
    // via the counter branch, not the non-animating short-circuit.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["inner_thought": "musing"]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: true,
      charsPerSecond: 60
    )
    #expect(row.shouldRevealThoughtSection(visibleChars: 0) == true)
  }
}
