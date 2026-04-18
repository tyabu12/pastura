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
}
