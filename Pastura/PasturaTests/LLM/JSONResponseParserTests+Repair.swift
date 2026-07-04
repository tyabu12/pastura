import Testing

@testable import Pastura

/// A2 repair-pipeline tests for ``JSONResponseParser`` (#194 PR#a Item 2).
///
/// Split from `JSONResponseParserTests.swift` to keep that file under
/// the `file_length` lint budget. Per `.claude/rules/testing.md`, this
/// file declares an `extension` of the existing `@Suite` rather than a
/// new suite — Swift Testing runs `@Suite`s in parallel by default, and
/// a separate suite would race against the original on shared state.
///
/// Each test below maps to one or more of the round-1 critic-derived
/// requirements:
///   R1#9 — Japanese-comma values, embedded JSON, missing-colon throw,
///          repair-then-fail (covered by guard test)
///   R2#2 — unclosed-string last-value-only guard
///   R2#3 — string-aware brace counter (verified via embedded-JSON case)
extension JSONResponseParserTests {

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

  // Multi-object input — the balanced scan finds the first complete object
  // but sees an object-like trailing residue (`{"b":2}`), so it returns the
  // input unchanged rather than salvaging the first object. A second whole
  // object is a strong instability signal: re-roll the inference for a
  // cleaner sample instead of silently accepting a possibly off-persona
  // first answer (#751 hybrid). The concatenated span then fails to parse →
  // throw.
  @Test func throwsOnMultipleObjectsInput() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(#"{"a":1}{"b":2}"#, expectedKeys: [])
    }
  }

  // Hybrid boundary (#751): an object-like trailing residue triggers the
  // multi-object throw even when that residue is itself incomplete — the
  // `{`-start is the signal, not its validity. Distinguishes this path from
  // `discardsTrailingProseAfterObject` (residue NOT starting with `{` →
  // salvaged).
  @Test func throwsWhenTrailingResidueIsObjectLike() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(#"{"statement": "hi"} {"oops"#, expectedKeys: [])
    }
  }

  // MARK: - Schema-guarded multi-object salvage (#907)

  // Reflect's `{ note }` failure shape: the model completes a schema-valid
  // first object then keeps emitting fabricated ASCII-only objects. With a
  // non-empty schema the salvage extracts the first object (ignoring the
  // #751 object-like-residue refusal) and reports `multi_object_salvage`.
  @Test func salvagesFirstObjectWhenSchemaGuardPasses() throws {
    let (output, kind) = try parser.parse(
      #"{"note": "watch Alice"}{"vote_strategy": "fabricated"}"#,
      expectedKeys: ["note"])
    #expect(output.fields["note"] == "watch Alice")
    #expect(kind == "multi_object_salvage")
  }

  // Posture pin (#751): the SAME multi-object raw with an EMPTY schema keeps
  // the refusal — no salvage, the concatenated span fails to parse → throw.
  @Test func multiObjectStillThrowsWithoutSchema() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(
        #"{"note": "watch Alice"}{"vote_strategy": "fabricated"}"#,
        expectedKeys: [])
    }
  }

  // Salvage only fires when the FIRST object carries all expected keys with
  // content. First object missing the required key → fall through to the
  // repair pipeline, which can't salvage the balanced multi-object span →
  // throw (no off-schema fabrication).
  @Test func multiObjectThrowsWhenFirstObjectMissingExpectedKey() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(
        #"{"statement": "hi"}{"note": "too late"}"#,
        expectedKeys: ["note"])
    }
  }

  // First object present-but-empty for the required key → salvage rejects it
  // (empty value fails the schema guard) → fall through → throw.
  @Test func multiObjectThrowsWhenFirstObjectHasEmptyExpectedKey() {
    #expect(throws: LLMError.self) {
      _ = try parser.parse(
        #"{"note": ""}{"note": "later"}"#,
        expectedKeys: ["note"])
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
