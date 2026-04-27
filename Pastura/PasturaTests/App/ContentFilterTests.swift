import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ContentFilterTests {
  @Test func filterReplacesBlockedJapaneseWords() {
    let filter = ContentFilter(blockedPatterns: ["殺す", "死ね"])
    let result = filter.filter("お前を殺すぞ、死ね")
    #expect(result == "お前を***ぞ、***")
  }

  @Test func filterReplacesBlockedEnglishWordsCaseInsensitive() {
    let filter = ContentFilter(blockedPatterns: ["fuck", "shit"])
    let result = filter.filter("What the Fuck is this Shit")
    #expect(result == "What the *** is this ***")
  }

  @Test func filterPreservesCleanText() {
    let filter = ContentFilter()
    let clean = "こんにちは、素晴らしい天気ですね"
    #expect(filter.filter(clean) == clean)
  }

  @Test func filterUsesCustomReplacement() {
    let filter = ContentFilter(blockedPatterns: ["bad"], replacement: "[FILTERED]")
    #expect(filter.filter("This is bad") == "This is [FILTERED]")
  }

  @Test func filterTurnOutputFiltersAllFields() {
    let filter = ContentFilter(blockedPatterns: ["殺す"])
    let output = TurnOutput(fields: [
      "statement": "殺すべきだ",
      "inner_thought": "殺す計画を立てよう",
      "reason": "安全な理由"
    ])
    let filtered = filter.filter(output)
    #expect(filtered.statement == "***べきだ")
    #expect(filtered.innerThought == "***計画を立てよう")
    #expect(filtered.reason == "安全な理由")
  }

  @Test func filterHandlesEmptyString() {
    let filter = ContentFilter()
    #expect(filter.filter("") == "")
  }

  @Test func filterHandlesMultipleOccurrences() {
    let filter = ContentFilter(blockedPatterns: ["bad"])
    #expect(filter.filter("bad bad bad") == "*** *** ***")
  }

  // MARK: - Default partition (ADR-005 §10.1)

  @Test func defaultFilterCatchesViolenceTermsAtOutput() {
    // Defense-in-depth check: violence is excluded from the input
    // validator but MUST be caught at output time. If this regresses,
    // the LLM could emit raw violence-topic content unfiltered.
    let filter = ContentFilter()
    #expect(filter.filter("人を殺す").contains("***"))
    #expect(filter.filter("殺人事件").contains("***"))
  }
}
