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
}
