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
}
