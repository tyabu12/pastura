import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct TypingPunctuationTests {
  @Test func sentenceTerminatorsGet300ms() {
    #expect(punctuationPauseMs(after: "。") == 300)
    #expect(punctuationPauseMs(after: ".") == 300)
    #expect(punctuationPauseMs(after: "!") == 300)
    #expect(punctuationPauseMs(after: "?") == 300)
    #expect(punctuationPauseMs(after: "！") == 300)
    #expect(punctuationPauseMs(after: "？") == 300)
    #expect(punctuationPauseMs(after: "…") == 300)
  }

  @Test func commasGet120ms() {
    #expect(punctuationPauseMs(after: "、") == 120)
    #expect(punctuationPauseMs(after: ",") == 120)
    #expect(punctuationPauseMs(after: "，") == 120)
  }

  @Test func regularCharactersGetNoPause() {
    #expect(punctuationPauseMs(after: "a") == 0)
    #expect(punctuationPauseMs(after: "あ") == 0)
    #expect(punctuationPauseMs(after: "漢") == 0)
    #expect(punctuationPauseMs(after: " ") == 0)
    #expect(punctuationPauseMs(after: "\n") == 0)
    #expect(punctuationPauseMs(after: ":") == 0)
    #expect(punctuationPauseMs(after: ";") == 0)
  }

  // MARK: - typingDurationMs (proportional turn-dwell floor estimate)
  //
  // Hand-computed against the exact AgentOutputRow reveal-loop model
  // (`AgentOutputRow.startAnimationIfNeeded`): N base ticks of 1000/cps ms
  // (ceil'd over the total), plus `punctuationPauseMs` summed per revealed
  // character, plus one `statementToThoughtPauseMs` boundary beat iff both
  // primary and thought are non-empty.

  @Test func durationShortStatementNoThought() {
    // "Hi." → base ceil(3/30*1000)=100, '.'=300, no boundary.
    #expect(typingDurationMs(primary: "Hi.", thought: "", charsPerSecond: 30) == 400)
  }

  @Test func durationVoteArrowPlusReason() {
    // "→ Bob" (5 chars, no punctuation) + "Risky." (6 chars, '.'=300).
    // base ceil(11/30*1000)=367, punctuation 300, boundary 300.
    #expect(
      typingDurationMs(primary: "→ Bob", thought: "Risky.", charsPerSecond: 30) == 967)
  }

  @Test func durationCommaHeavyNoThought() {
    // "A, b, c." (8 chars): base ceil(8/30*1000)=267, ','+','+'.'=120+120+300=540.
    #expect(
      typingDurationMs(primary: "A, b, c.", thought: "", charsPerSecond: 30) == 807)
  }

  @Test func durationStatementThoughtBoundaryBeat() {
    // "Hello world"(11) + "thinking"(8) = 19 chars, no punctuation.
    // base ceil(19/30*1000)=634, boundary 300.
    #expect(
      typingDurationMs(primary: "Hello world", thought: "thinking", charsPerSecond: 30)
        == 934)
  }

  @Test func durationNoBoundaryWhenPrimaryEmpty() {
    // Empty primary + non-empty thought: the reveal loop never hits the
    // `newPosition == primaryLen(0)` boundary, so no 300ms beat.
    // "ok" (2 chars): base ceil(2/30*1000)=67, no punctuation, no boundary.
    #expect(typingDurationMs(primary: "", thought: "ok", charsPerSecond: 30) == 67)
  }

  @Test func durationZeroForNonPositiveCharsPerSecond() {
    // cps <= 0 mirrors AgentOutputRow's `cps > 0` guard → snap to full, no dwell.
    #expect(typingDurationMs(primary: "Hi.", thought: "x", charsPerSecond: 0) == 0)
    #expect(typingDurationMs(primary: "Hi.", thought: "x", charsPerSecond: -5) == 0)
  }

  @Test func durationZeroForEmptyText() {
    #expect(typingDurationMs(primary: "", thought: "", charsPerSecond: 30) == 0)
  }

  // MARK: - remainingTypingDurationMs (reveal-position handoff)
  //
  // `seed` is a position in the combined `[primary][thought]` reveal space
  // (what `AgentOutputRow.visibleChars` counts). The estimate covers only the
  // unrevealed remainder, mirroring the reveal loop continuing from `seed`:
  // the already-elapsed prefix (and its punctuation pauses) is excluded, and
  // the statement→thought boundary beat is counted only while the remaining
  // primary is non-empty (boundary not yet crossed).

  @Test func remainingSeedZeroEqualsFull() {
    #expect(
      remainingTypingDurationMs(
        seed: 0, primary: "→ Bob", thought: "Risky.", charsPerSecond: 30)
        == typingDurationMs(primary: "→ Bob", thought: "Risky.", charsPerSecond: 30))
  }

  @Test func remainingMidPrimaryDropsRevealedPrefix() {
    // "Hello world"(11), seed 6 → remaining "world"(5) + "ok"(2) = 7 chars.
    // base ceil(7/30*1000)=234, no punctuation, boundary 300 (primary non-empty).
    #expect(
      remainingTypingDurationMs(
        seed: 6, primary: "Hello world", thought: "ok", charsPerSecond: 30) == 534)
  }

  @Test func remainingPastPrimaryNoBoundaryBeat() {
    // primary "Hi"(2), thought "thinking"(8), seed 4 → remaining thought
    // "inking"(6), no boundary (primary already done). base ceil(6/30*1000)=200.
    #expect(
      remainingTypingDurationMs(
        seed: 4, primary: "Hi", thought: "thinking", charsPerSecond: 30) == 200)
  }

  @Test func remainingExcludesAlreadyRevealedPunctuation() {
    // primary "A, b, c."(8), seed 2 → "A," already revealed (its 120ms comma
    // pause already elapsed). Remaining " b, c."(6): base 200, ','=120 + '.'=300.
    #expect(
      remainingTypingDurationMs(
        seed: 2, primary: "A, b, c.", thought: "", charsPerSecond: 30) == 620)
  }

  @Test func remainingSeedAtPrimaryBoundaryNoBeat() {
    // seed == primary.count: boundary already crossed, remaining = thought only.
    // primary "Hi"(2), thought "ok"(2) → "" + "ok": base ceil(2/30*1000)=67.
    #expect(
      remainingTypingDurationMs(
        seed: 2, primary: "Hi", thought: "ok", charsPerSecond: 30) == 67)
  }

  @Test func remainingFullyRevealedIsZero() {
    #expect(
      remainingTypingDurationMs(
        seed: 13, primary: "Hi.", thought: "thought", charsPerSecond: 30) == 0)
    #expect(
      remainingTypingDurationMs(
        seed: 99, primary: "Hi.", thought: "", charsPerSecond: 30) == 0)
  }

  @Test func remainingZeroForNonPositiveCps() {
    #expect(
      remainingTypingDurationMs(
        seed: 1, primary: "Hi.", thought: "x", charsPerSecond: 0) == 0)
  }
}
