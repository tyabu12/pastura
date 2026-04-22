import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
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

  // MARK: - 21. Hallucinated conversation continuation after <|im_end|>

  @Test func truncatesHallucinatedContinuation() throws {
    let input = """
      {"inner_thought": "考え中", "statement": "こんにちは"}<|im_end|>
      <|im_start|>user
      サクラ: 別の発言"}
      <|im_end|>
      <|im_start|>assistant
      {"inner_thought": "次の
      """
    let output = try parser.parse(input)
    #expect(output.fields["inner_thought"] == "考え中")
    #expect(output.fields["statement"] == "こんにちは")
  }

  // MARK: - 22. <think> tags + code block combined

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

  // MARK: - 23. Raw-text propagation (#194)

  // The unmodified input text must travel with the parsed TurnOutput so
  // SimulationViewModel.persistTurnRecord can store it in TurnRecord.rawOutput.
  // Uses an input that exercises the full cleanup pipeline (thinking tag +
  // code block) — rawText must remain the ORIGINAL, not the cleaned form.
  @Test func preservesRawTextThroughCleanupPipeline() throws {
    let input = """
      <|channel>thought
      thinking...
      <channel|>```json
      {"statement": "hi"}
      ```
      """
    let output = try parser.parse(input)
    #expect(output.fields["statement"] == "hi")
    #expect(output.rawText == input, "rawText should preserve the original pre-cleanup input")
  }

  // MARK: - 24. A2 repair pipeline (#194 PR#a Item 2)
  //
  // Each test below maps to one or more of the round-1 critic-derived
  // requirements:
  //   R1#9 — Japanese-comma values, embedded JSON, missing-colon throw,
  //          repair-then-fail (covered by guard test)
  //   R2#2 — unclosed-string last-value-only guard
  //   R2#3 — string-aware brace counter (verified via embedded-JSON case)

  // Happy path: well-formed input parses cleanly, repair kind is nil.
  @Test func repairKindIsNilForWellFormedInput() throws {
    let (_, kind) = try parser.parse(
      #"{"statement": "hello"}"#, expectedKeys: [])
    #expect(kind == nil)
  }

  // Trailing commas in objects/arrays are accepted by Apple's
  // `JSONSerialization` since iOS 17 — they parse as-is without repair
  // (kind == nil). This test pins that behaviour so a regression to a
  // stricter parser version doesn't silently degrade Hyp A coverage.
  @Test func trailingCommaInObjectParsesWithoutRepair() throws {
    let (output, kind) = try parser.parse(
      #"{"statement": "hi", "action": "betray",}"#, expectedKeys: [])
    #expect(output.fields["statement"] == "hi")
    #expect(output.fields["action"] == "betray")
    #expect(kind == nil)
  }

  @Test func trailingCommaInArrayParsesWithoutRepair() throws {
    let (output, kind) = try parser.parse(
      #"{"options": ["a", "b",]}"#, expectedKeys: [])
    #expect(output.fields["options"] != nil)
    #expect(kind == nil)
  }

  // Unclosed string + missing brace — both repairs fire as a composite.
  @Test func repairsUnclosedStringAsLastValue() throws {
    let (output, kind) = try parser.parse(
      #"{"statement": "hello"#, expectedKeys: [])
    #expect(output.fields["statement"] == "hello")
    #expect(kind == "unclosed_string+unclosed_brace")
  }

  // Unclosed brace alone — string is properly closed, just missing `}`.
  @Test func repairsUnclosedBraceOnly() throws {
    let (output, kind) = try parser.parse(
      #"{"statement": "hi""#, expectedKeys: [])
    #expect(output.fields["statement"] == "hi")
    #expect(kind == "unclosed_brace")
  }

  // Truncated stream ending with dangling `,` — `closeUnclosedBraces`
  // strips the comma and appends `}`. Reported as `unclosed_brace`
  // because the missing closer is the load-bearing repair; the comma
  // strip is housekeeping inside that step (no separate kind).
  @Test func repairsDanglingCommaAndUnclosedBrace() throws {
    let (output, kind) = try parser.parse(
      #"{"statement": "hi","#, expectedKeys: [])
    #expect(output.fields["statement"] == "hi")
    #expect(kind == "unclosed_brace")
  }

  // R1#9 — Japanese ideographic comma `、` inside string is well-formed
  // content. Verifies the parser flows through unchanged (no repair
  // tripped, content preserved as-is).
  @Test func preservesJapaneseCommasInsideStringValues() throws {
    let input = #"{"statement": "はい、そうです"}"#
    let (output, kind) = try parser.parse(input, expectedKeys: [])
    #expect(output.fields["statement"] == "はい、そうです")
    #expect(kind == nil)
  }

  // ASCII commas inside string values must survive intact through the
  // repair pipeline (would matter if a future repair started touching
  // commas — guard against regression).
  @Test func preservesAsciiCommasInsideStringValues() throws {
    let input = #"{"statement": "hello, world"}"#
    let (output, kind) = try parser.parse(input, expectedKeys: [])
    #expect(output.fields["statement"] == "hello, world")
    #expect(kind == nil)
  }

  // R1#9 — embedded JSON in string content. Brace counter must respect
  // string context (the inner `{`/`}` are content).
  @Test func handlesEmbeddedJSONInStringValues() throws {
    let input = #"{"statement": "答えは{\"a\":1}です"}"#
    let (output, kind) = try parser.parse(input, expectedKeys: [])
    #expect(output.fields["statement"] == #"答えは{"a":1}です"#)
    #expect(kind == nil)
  }

  // R1#9 — missing colon must throw, not fabricate a value.
  @Test func throwsOnMissingColon() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(#"{"key" "value"}"#, expectedKeys: [])
    }
  }

  // Mid-key truncation has an even quote count → no unclosed-string
  // repair runs; the brace-close repair appends `}` but the resulting
  // `{"a":"v1","action"}` is still malformed (key without value), so
  // the guard rejects.
  @Test func throwsOnTruncatedMidKey() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(
        #"{"statement": "hello", "action"#, expectedKeys: [])
    }
  }

  // Schema-aware guard: repair "succeeds" syntactically but the parsed
  // output is missing a required key → reject and throw.
  @Test func rejectsRepairWhenSchemaGuardFails() {
    // Repair would yield {"statement": "hi"} but the choose-phase schema
    // requires `action` — missing → throw, no fabricated commit.
    #expect(throws: LLMError.self) {
      _ = try parser.parse(
        #"{"statement": "hi","#,
        expectedKeys: ["statement", "action"])
    }
  }

  // Schema-aware guard accepts when all expected keys are present and
  // non-empty after repair.
  @Test func acceptsRepairWhenSchemaGuardPasses() throws {
    let (output, kind) = try parser.parse(
      #"{"statement": "hi", "action": "betray","#,
      expectedKeys: ["statement", "action"])
    #expect(output.fields["statement"] == "hi")
    #expect(output.fields["action"] == "betray")
    #expect(kind == "unclosed_brace")
  }

  // Schema-aware guard rejects when a repair produces the key but with
  // empty value. Repair fires (closes the unclosed string + brace),
  // schema check sees `action == ""` → reject.
  @Test func rejectsRepairWithEmptyExpectedField() {
    // Truncated with empty action that would otherwise repair cleanly.
    #expect(throws: LLMError.self) {
      _ = try parser.parse(
        #"{"statement": "hi", "action": ""#,
        expectedKeys: ["statement", "action"])
    }
  }

  // Multi-object input — existing greedy `\{.*\}` regex captures the
  // whole span; repair pipeline must not "fix" it into a single fake
  // object.
  @Test func throwsOnMultipleObjectsInput() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(#"{"a":1}{"b":2}"#, expectedKeys: [])
    }
  }

  // Fully empty / unparseable → throw, no fake fabrication.
  @Test func throwsOnFullyMalformedInput() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(#"completely not json"#, expectedKeys: [])
    }
  }

  // Backward-compat: the legacy `parse(_:)` overload (no expectedKeys)
  // must still throw for malformed input — single-arg callers are not
  // accidentally getting the repair guard relaxed.
  @Test func legacyParseStillThrowsOnMalformed() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(#"completely not json"#)
    }
  }

  // Backward-compat: the legacy `parse(_:)` overload still benefits
  // from repair (no schema guard since expectedKeys is empty).
  @Test func legacyParseStillRepairsRecoverableInput() throws {
    let output = try parser.parse(#"{"statement": "hi","#)
    #expect(output.fields["statement"] == "hi")
  }
}
