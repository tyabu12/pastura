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

  /// **The end arm's own header-echo case (#1452).** A *leading* non-ChatML end
  /// marker is the model echoing its template's turn boundary with the payload
  /// still behind it. Cutting at index 0 destroyed the payload deterministically
  /// (the template reproduces on every retry) → an ADR-021 turn skip.
  ///
  /// Revert the non-ChatML end arm's search origin to `0` and this test throws.
  @Test func endMarker_leadingHeaderEcho_isNotATurnBoundary() throws {
    let input = """
      <turn|>
      <|turn>model
      {"statement": "本物", "action": "cooperate"}
      """

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "本物")
    #expect(output.fields["action"] == "cooperate")
  }

  /// The gate is a search *origin*, not a per-text skip: a leading marker is
  /// stepped over and the next occurrence after the first structural `{` still
  /// cuts, so a fabricated continuation behind a header echo is not accepted.
  @Test func endMarker_leadingEchoThenFabricatedContinuation_cutsAtSecond() throws {
    let input = """
      <turn|>
      <|turn>model
      {"statement": "本物", "action": "cooperate"}<turn|>
      <|turn>model
      ```json
      {"statement": "偽物", "action": "betray"}
      ```
      """

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "本物")

    // Negative control — without the Gemma pair the fenced continuation wins.
    let unfixed = try parser.parse(input, turnMarkers: [.chatML])
    #expect(unfixed.fields["statement"] == "偽物")
  }

  /// **Control — byte-identical-for-ChatML criterion.** ChatML's own end marker
  /// is *not* gated: a leading `<|im_end|>` still cuts at index 0 under either
  /// set, so `<|im_end|>{"fake":1}` keeps failing and retrying rather than
  /// becoming an accepted fabricated object (#1422's reason for not gating
  /// every marker). A failure here means someone widened the gate to ChatML.
  @Test func endMarker_chatMLLeadingMarker_stillDestroysPayload() throws {
    #expect(throws: LLMError.self) {
      try parser.parse(#"<|im_end|>{"fake":1}"#, turnMarkers: [.chatML])
    }
    // Same marker under Gemma's effective set: the gate keys on the marker
    // literal, not on which model is loaded.
    #expect(throws: LLMError.self) {
      try parser.parse("<|im_end|>\n{\"statement\": \"本物\"}", turnMarkers: gemma)
    }
  }

  /// **A pin on the accepted trade, not desired behaviour.** For a non-ChatML
  /// marker the fabricated-turn shape — end marker, then an object with nothing
  /// before it — is accepted: the object is the only candidate, and failing it
  /// deterministically would be the #1452 skip again. Pre-#1422 Gemma had no
  /// end arm at all, so this is also the behaviour that shipped before that PR.
  @Test func endMarker_leadingMarkerThenObject_isAccepted_acceptedTrade() throws {
    let output = try parser.parse(#"<turn|>{"statement": "偽物"}"#, turnMarkers: gemma)
    #expect(output.fields["statement"] == "偽物")
  }

  /// With no structural `{` anywhere the gate has no origin and the arm falls
  /// back to the from-0 search; there is nothing to salvage either way.
  @Test func endMarker_noStructuralBrace_stillFails() throws {
    #expect(throws: LLMError.self) {
      try parser.parse("<turn|>\n<|turn>model\nただの文章", turnMarkers: gemma)
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
