import Testing

@testable import Pastura

struct JSONResponseParserTests {
  let parser = JSONResponseParser()

  // MARK: - 1. Clean JSON

  @Test func parsesCleanJSON() throws {
    let input = #"{"statement": "hello", "action": "cooperate"}"#
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "hello")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - 2. Gemma 4 thinking tags (real E2B output sample)

  @Test func stripsGemma4ThinkingTags() throws {
    let input = """
      <|channel>thought
      I need to cooperate because the opponent has been friendly.
      Let me think about this carefully.
      <channel|>{"statement": "Let's work together", "action": "cooperate"}
      """
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "Let's work together")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - 3. Code block with json label

  @Test func extractsFromJsonCodeBlock() throws {
    let input = """
      ```json
      {"vote": "Alice", "reason": "She is trustworthy"}
      ```
      """
    let output = try parser.parse(input)
    #expect(output.fields["vote"] == "Alice")
    #expect(output.fields["reason"] == "She is trustworthy")
  }

  // MARK: - 4. Code block without label

  @Test func extractsFromUnlabeledCodeBlock() throws {
    let input = """
      ```
      {"boke": "Why did the chicken cross the road?"}
      ```
      """
    let output = try parser.parse(input)
    #expect(output.fields["boke"] == "Why did the chicken cross the road?")
  }

  // MARK: - 5. Leading garbage text

  @Test func handlesLeadingGarbage() throws {
    let input = #"Here is my response: {"action": "betray", "reason": "strategic"}"#
    let output = try parser.parse(input)
    #expect(output.fields["action"] == "betray")
    #expect(output.fields["reason"] == "strategic")
  }

  // MARK: - 6. Numeric values normalized to String

  @Test func normalizesNumericValues() throws {
    let input = #"{"score": 42, "ratio": 3.14}"#
    let output = try parser.parse(input)
    #expect(output.fields["score"] == "42")
    #expect(output.fields["ratio"] == "3.14")
  }

  // MARK: - 7. Boolean values normalized to String

  @Test func normalizesBooleanValues() throws {
    let input = #"{"alive": true, "eliminated": false}"#
    let output = try parser.parse(input)
    #expect(output.fields["alive"] == "true")
    #expect(output.fields["eliminated"] == "false")
  }

  // MARK: - 8. Null values omitted

  @Test func omitsNullValues() throws {
    let input = #"{"statement": "hello", "extra": null}"#
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "hello")
    #expect(output.fields["extra"] == nil)
  }

  // MARK: - 9. Nested object normalized to JSON string

  @Test func normalizesNestedObjectToJSONString() throws {
    let input = #"{"data": {"key": "value"}, "statement": "hi"}"#
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "hi")
    // Nested object should be serialized as JSON string
    let dataValue = try #require(output.fields["data"])
    #expect(dataValue.contains("key"))
    #expect(dataValue.contains("value"))
  }

  // MARK: - 10. Invalid JSON throws LLMError.invalidResponse

  @Test func throwsOnInvalidJSON() {
    let input = "This is not JSON at all"
    #expect(throws: LLMError.self) {
      try parser.parse(input)
    }
  }

  // MARK: - 11. Thinking tags + code block combined

  @Test func handlesThinkingTagsAndCodeBlock() throws {
    let input = """
      <|channel>thought
      Analyzing the situation...
      <channel|>
      ```json
      {"inner_thought": "I should betray", "declaration": "I will cooperate"}
      ```
      """
    let output = try parser.parse(input)
    #expect(output.fields["inner_thought"] == "I should betray")
    #expect(output.fields["declaration"] == "I will cooperate")
  }

  // MARK: - 12. Empty input throws

  @Test func throwsOnEmptyInput() {
    #expect(throws: LLMError.self) {
      try parser.parse("")
    }
  }

  // MARK: - 13. Japanese text in values

  @Test func handlesJapaneseText() throws {
    let input = #"{"statement": "協力しましょう", "inner_thought": "本当は裏切りたい"}"#
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "協力しましょう")
    #expect(output.fields["inner_thought"] == "本当は裏切りたい")
  }

  // MARK: - 14. <think> tags (common thinking model format)

  @Test func stripsThinkTags() throws {
    let input = """
      <think>
      I need to cooperate because the opponent has been friendly.
      Let me think about this carefully.
      </think>
      {"statement": "Let's work together", "action": "cooperate"}
      """
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "Let's work together")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - 15. <think> tags on single line

  @Test func stripsSingleLineThinkTags() throws {
    let input = #"<think>short thought</think>{"statement": "hello", "action": "cooperate"}"#
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "hello")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - 16. <|channel>thought without mandatory newline

  @Test func stripsChannelThinkingTagWithoutNewline() throws {
    let input = """
      <|channel>thought I need to cooperate.<channel|>{"statement": "ok", "action": "cooperate"}
      """
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "ok")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - 17. Thinking content with embedded JSON-like text

  @Test func stripsThinkTagsWithEmbeddedJSON() throws {
    let input = """
      <think>I'll respond with {"wrong": "data"} as my strategy</think>
      {"correct": "data", "action": "cooperate"}
      """
    let output = try parser.parse(input)
    #expect(output.fields["correct"] == "data")
    #expect(output.fields["action"] == "cooperate")
    #expect(output.fields["wrong"] == nil)
  }

  // MARK: - 18. Channel thinking tag with embedded JSON-like text

  @Test func stripsChannelTagsWithEmbeddedJSON() throws {
    let input = """
      <|channel>thought
      I considered {"wrong": "data"} but decided against it.
      <channel|>
      {"correct": "data", "action": "betray"}
      """
    let output = try parser.parse(input)
    #expect(output.fields["correct"] == "data")
    #expect(output.fields["action"] == "betray")
    #expect(output.fields["wrong"] == nil)
  }

  // MARK: - 19. Trailing end-of-turn token (<|im_end|>)

  @Test func stripsTrailingImEndToken() throws {
    let input = #"{"statement": "こんにちは", "inner_thought": "様子を見よう"}<|im_end|>"#
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "こんにちは")
    #expect(output.fields["inner_thought"] == "様子を見よう")
  }

  // MARK: - 20. Trailing end-of-turn token with whitespace

  @Test func stripsTrailingImEndTokenWithWhitespace() throws {
    let input = """
      {"statement": "hello", "action": "cooperate"} <|im_end|>
      """
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "hello")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - 21. <think> tags + code block combined

  @Test func handlesThinkTagsAndCodeBlock() throws {
    let input = """
      <think>
      Let me analyze the situation...
      </think>
      ```json
      {"inner_thought": "I should betray", "declaration": "I will cooperate"}
      ```
      """
    let output = try parser.parse(input)
    #expect(output.fields["inner_thought"] == "I should betray")
    #expect(output.fields["declaration"] == "I will cooperate")
  }
}
