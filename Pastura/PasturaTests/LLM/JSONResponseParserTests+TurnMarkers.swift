import Testing

@testable import Pastura

/// Per-model hallucinated-turn truncation (#1422). Sibling extension of the
/// existing suite rather than a new one, per `.claude/rules/testing.md`
/// § "Splitting a Suite Across Files".
///
/// Every test that asserts the fix also runs the **same input** through the
/// pre-#1422 ChatML-only set as a negative control — otherwise a test that
/// happens to pass for an unrelated reason (the balanced-brace scan already
/// discards trailing prose) would read as proof truncation fired.
extension JSONResponseParserTests {
  private var gemma: [ChatTurnMarkers] {
    [ChatTurnMarkers(start: "<|turn>", end: "<turn|>"), .chatML]
  }

  // MARK: - End arm

  /// A fenced fabricated continuation loses the payload: `extractFromCodeBlock`
  /// runs before the balanced-brace scan and takes `firstMatch`
  /// unconditionally, discarding the real unfenced answer.
  @Test func endMarker_truncatesFencedFabricatedContinuation() throws {
    let input = """
      {"statement": "本物", "action": "cooperate"}<turn|>
      <|turn>user
      もう一度
      <turn|>
      <|turn>model
      ```json
      {"statement": "偽物", "action": "betray"}
      ```
      """

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "本物")
    #expect(output.fields["action"] == "cooperate")

    // Negative control — the pre-#1422 behaviour on the identical input.
    let unfixed = try parser.parse(input, turnMarkers: [.chatML])
    #expect(unfixed.fields["statement"] == "偽物")
  }

  /// **A pin on an accepted trade-off, not desired behaviour.** Read
  /// [#1452](https://github.com/tyabu12/pastura/issues/1452) before changing —
  /// a failure means the unguarded cut moved, not that this is stale.
  ///
  /// The end arm cuts at the first occurrence with no `firstBrace` gate, so a *leading*
  /// end marker discards the whole payload the model then writes.
  /// The symmetric-looking fix — reusing the start arm's `> firstBrace` gate —
  /// is not strictly safer: the second `#expect` shows `<|im_end|>{"fake":1}`
  /// would then be accepted rather than failing and retrying.
  @Test func endMarker_leadingMarkerDestroysPayload_acceptedGap() throws {
    let leadingEcho = """
      <turn|>
      {"statement": "本物", "action": "cooperate"}
      """
    #expect(throws: LLMError.self) { try parser.parse(leadingEcho, turnMarkers: gemma) }

    // The counter-example that blocks the `> firstBrace` gate: gating the end
    // arm would turn this throw into an accepted fabricated object.
    #expect(throws: LLMError.self) {
      try parser.parse(#"<|im_end|>{"fake":1}"#, turnMarkers: [.chatML])
    }
  }

  /// **Regression.** A non-ChatML end marker inside a string value is payload,
  /// not a boundary — pre-fix measured as `["statement": "テンプレートは"]` with
  /// `action` gone. Reachable because `stopSequence` strips only `<|im_end|>`
  /// (#1451), so `<turn|>` survives un-stripped.
  @Test func endMarker_insideStringValue_isNotATurnBoundary() throws {
    let input = #"{"statement": "テンプレートは <turn|> で終わる", "action": "cooperate"}"#

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "テンプレートは <turn|> で終わる")
    #expect(output.fields["action"] == "cooperate")
  }

  /// **Control — byte-identical-for-ChatML criterion.** ChatML's own end
  /// marker still cuts string-blind (keyed on `.chatML.end` by literal). A
  /// failure means someone widened the guard — a separate decision from
  /// #1422, and it changes Qwen.
  @Test func endMarker_chatMLInsideStringValue_stillCutsBlind() throws {
    let input = #"{"note": "テンプレートは <|im_end|> で終わる"}"#

    let (output, repair) = try parser.parse(
      input, expectedKeys: ["note"], turnMarkers: [.chatML])
    #expect(output.fields["note"] == "テンプレートは")
    #expect(repair == "unclosed_string+unclosed_brace")
  }

  // MARK: - Start arm

  /// A start marker after the first structural `{` is a fabricated next turn,
  /// so it truncates — covers the hallucination shape with no end marker.
  @Test func startMarker_afterFirstBrace_truncates() throws {
    let input = """
      {"statement": "本物"}
      <|turn>model
      ```json
      {"statement": "偽物"}
      ```
      """

    #expect(try parser.parse(input, turnMarkers: gemma).fields["statement"] == "本物")
    #expect(try parser.parse(input, turnMarkers: [.chatML]).fields["statement"] == "偽物")
  }

  /// **The asymmetry's load-bearing half.** A leading start marker is the
  /// model echoing its own template header; truncating there deterministically
  /// deletes the payload.
  ///
  /// Revert the `firstBrace + 1` search origin to `0` and this test throws
  /// while every other test here still passes.
  @Test func startMarker_leadingHeaderEcho_isNotATurnBoundary() throws {
    let input = """
      <|turn>model
      {"statement": "本物", "action": "cooperate"}
      """

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "本物")
    #expect(output.fields["action"] == "cooperate")
  }

  /// The start arm is string-aware: a marker inside a JSON string value is
  /// payload content, not a turn boundary. Without the check the cut lands
  /// mid-string and a silently-truncated value is persisted as the answer.
  @Test func startMarker_insideStringValue_isNotATurnBoundary() throws {
    let input = #"{"statement": "テンプレートは <|im_start|> から始まる", "action": "cooperate"}"#

    let output = try parser.parse(input, turnMarkers: [.chatML])
    #expect(output.fields["statement"] == "テンプレートは <|im_start|> から始まる")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - Qwen / ChatML equivalence

  /// The end arm is byte-identical for every backend, and the start arm is a
  /// no-op on inputs with no post-`{` start marker — every input in the
  /// shipped corpus. Demonstrated on the trailing-prose residue shape.
  @Test func markerFreeInput_parsesIdenticallyUnderEitherSet() throws {
    let input = """
      {"statement": "hello", "action": "cooperate"}
      That is my answer for this round.
      """

    let chatML = try parser.parse(input, turnMarkers: [.chatML])
    let withGemma = try parser.parse(input, turnMarkers: gemma)
    #expect(chatML.fields == withGemma.fields)
    #expect(chatML.fields["statement"] == "hello")
  }

  /// A ChatML model's own hallucination shape is unaffected by the widened
  /// set — the extra Gemma pair simply never matches.
  @Test func chatMLHallucination_unchangedWhenGemmaPairIsAlsoPresent() throws {
    let input = """
      {"inner_thought": "考え中", "statement": "こんにちは"}<|im_end|>
      <|im_start|>user
      サクラ: 別の発言"}
      <|im_end|>
      """

    let baseline = try parser.parse(input, turnMarkers: [.chatML])
    let widened = try parser.parse(input, turnMarkers: gemma)
    #expect(baseline.fields == widened.fields)
    #expect(widened.fields["statement"] == "こんにちは")
  }

  // MARK: - Degenerate inputs

  /// An empty marker string must never match. It's `firstIndex`'s own
  /// `guard !pattern.isEmpty` that stops the index-0 cut, so deleting only the
  /// three `isEmpty` checks inside `truncateAtTurnMarkers` destroys nothing —
  /// all four together are what hold. An empty pair goes **inert** rather than
  /// over-matching, which is why `ModelRegistryTurnMarkerDivergenceTests`
  /// asserts non-empty markers at the catalog instead.
  @Test func emptyMarkerStrings_areIgnored() throws {
    let input = #"{"statement": "hello"}"#
    let output = try parser.parse(
      input, turnMarkers: [ChatTurnMarkers(start: "", end: "")])
    #expect(output.fields["statement"] == "hello")
  }

  @Test func emptyMarkerSet_leavesTextUntouched() throws {
    let input = #"{"statement": "hello"}<|im_end|>garbage"#
    let output = try parser.parse(input, turnMarkers: [])
    #expect(output.fields["statement"] == "hello")
  }
}
