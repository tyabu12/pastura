import Testing

@testable import Pastura

/// Per-model hallucinated-turn truncation (#1422). Sibling extension of the
/// existing suite rather than a new one, per `.claude/rules/testing.md`
/// § "Splitting a Suite Across Files".
///
/// Every test that asserts the fix also runs the **same input** through the
/// pre-#1422 ChatML-only set as a negative control — without one, a test that
/// happens to pass for an unrelated reason (the balanced-brace scan already
/// discards trailing prose, so most hallucination shapes parse correctly with
/// no truncation at all) would read as proof that truncation fired.
extension JSONResponseParserTests {
  private var gemma: [ChatTurnMarkers] {
    [ChatTurnMarkers(start: "<|turn>", end: "<turn|>"), .chatML]
  }

  // MARK: - End arm

  /// A fenced fabricated continuation is the shape that actually loses the
  /// payload: `extractFromCodeBlock` runs **before** the balanced-brace scan
  /// and takes `firstMatch` unconditionally, so it lifts the fabricated object
  /// out of the fence and the real (unfenced) answer is discarded silently.
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

  /// **A pin on an accepted trade-off, not an assertion of desired behaviour.**
  /// Read [#1452](https://github.com/tyabu12/pastura/issues/1452) before
  /// changing it — a failure here means the end arm's unguarded cut moved, and
  /// the question is whether #1452 was decided, not whether this expectation is
  /// stale.
  ///
  /// The end arm cuts at the first occurrence with no `firstBrace` guard, so a
  /// *leading* end marker discards the whole payload the model then writes.
  /// The symmetric-looking fix — reuse the start arm's `> firstBrace` gate —
  /// is not strictly safer, which is the second `#expect` below: today
  /// `<|im_end|>{"fake":1}` fails and retries; under that gate the fabricated
  /// object would be accepted as the turn's answer. Both arms stay as they are
  /// until #1452 picks a side.
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

  /// **Regression.** A non-ChatML end marker inside a JSON string value is
  /// payload content, not a turn boundary. Without the guard the cut lands
  /// mid-value, the repair pipeline closes the quote and brace, and a truncated
  /// value is persisted as the agent's answer — measured before the fix as
  /// `["statement": "テンプレートは"]` with `action` gone entirely.
  ///
  /// Reachable specifically because `stopSequence` still strips only
  /// `<|im_end|>` (#1451), so `<turn|>` is the first end marker that survives
  /// generation and arrives here un-stripped.
  @Test func endMarker_insideStringValue_isNotATurnBoundary() throws {
    let input = #"{"statement": "テンプレートは <turn|> で終わる", "action": "cooperate"}"#

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "テンプレートは <turn|> で終わる")
    #expect(output.fields["action"] == "cooperate")
  }

  /// **Control — the byte-identical-for-ChatML criterion.** The same shape with
  /// ChatML's *own* end marker still cuts string-blind, because guarding it
  /// would move shipped ChatML behaviour and #1422 holds that fixed. So the
  /// guard above is keyed on `.chatML.end` by literal, and this test is what
  /// pins the exception rather than letting it drift into "all end markers".
  ///
  /// A failure here means someone widened the guard. That may well be the right
  /// call on its own merits — but it is a separate decision from #1422, and it
  /// changes Qwen.
  @Test func endMarker_chatMLInsideStringValue_stillCutsBlind() throws {
    let input = #"{"note": "テンプレートは <|im_end|> で終わる"}"#

    let (output, repair) = try parser.parse(
      input, expectedKeys: ["note"], turnMarkers: [.chatML])
    #expect(output.fields["note"] == "テンプレートは")
    #expect(repair == "unclosed_string+unclosed_brace")
  }

  // MARK: - Start arm

  /// A start marker **after** the first structural `{` is a fabricated next
  /// turn, so it truncates — covering the hallucination shape that emits no
  /// end marker at all.
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

  /// **The asymmetry's load-bearing half.** A *leading* start marker is the
  /// model echoing its own template header with the payload still behind it.
  /// Truncating there deletes the payload — and deterministically, since the
  /// backend's template config reproduces on every retry, so the run walks
  /// `parse_failed` → `retriesExhausted` → an ADR-021 turn skip rather than
  /// recovering.
  ///
  /// Revert the `firstBrace + 1` search origin to `0` and this test throws
  /// while every other test in this file still passes.
  @Test func startMarker_leadingHeaderEcho_isNotATurnBoundary() throws {
    let input = """
      <|turn>model
      {"statement": "本物", "action": "cooperate"}
      """

    let output = try parser.parse(input, turnMarkers: gemma)
    #expect(output.fields["statement"] == "本物")
    #expect(output.fields["action"] == "cooperate")
  }

  /// The start arm is string-aware: a marker spelled inside a JSON string
  /// value is payload content, not a turn boundary. Without the check the cut
  /// lands mid-string, the repair pipeline closes the quote and brace, and a
  /// silently-truncated field value is persisted as if it were the model's
  /// answer.
  @Test func startMarker_insideStringValue_isNotATurnBoundary() throws {
    let input = #"{"statement": "テンプレートは <|im_start|> から始まる", "action": "cooperate"}"#

    let output = try parser.parse(input, turnMarkers: [.chatML])
    #expect(output.fields["statement"] == "テンプレートは <|im_start|> から始まる")
    #expect(output.fields["action"] == "cooperate")
  }

  // MARK: - Qwen / ChatML equivalence

  /// The end arm is byte-identical for every backend, and the start arm is a
  /// no-op on inputs that carry no post-`{` start marker — which is every
  /// input in the shipped corpus. Demonstrated on the trailing-prose residue
  /// shape, the one the balanced-brace scan handles on its own.
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

  /// An empty marker string must never match. The counterfactual is worth
  /// stating precisely: it is `firstIndex`'s own `guard !pattern.isEmpty` that
  /// stops the index-0 cut, so deleting only the three `isEmpty` checks inside
  /// `truncateAtTurnMarkers` destroys nothing — all four together are what
  /// hold. With them in place an empty pair does not over-match, it goes
  /// **inert**, and that inertness is *why*
  /// `ModelRegistryTurnMarkerDivergenceTests` asserts non-empty markers at the
  /// catalog — the mechanism is silent, so the catalog is the only place it can
  /// be caught.
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
