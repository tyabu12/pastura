import Testing

@testable import Pastura

/// Unit tests for ``StringStateMachine`` — the JSON string-literal state
/// tracker that A2 repair heuristics rely on (#194 PR#a Item 2).
///
/// The state machine is the load-bearing primitive that prevents repair
/// false-positives such as treating a comma inside a Japanese string
/// value as a trailing comma, or counting a `}` inside a string value
/// against the brace balance.
@Suite(.timeLimit(.minutes(1)))
struct StringStateMachineTests {

  // MARK: - Empty / trivial

  @Test func emptyTextHasZeroBalances() {
    let m = StringStateMachine("")
    #expect(m.unescapedQuoteCount == 0)
    #expect(m.braceBalance == 0)
    #expect(m.bracketBalance == 0)
    #expect(!m.hasUnclosedString)
  }

  @Test func wellFormedObjectIsBalanced() {
    let m = StringStateMachine(#"{"a": 1}"#)
    #expect(m.braceBalance == 0)
    #expect(m.unescapedQuoteCount == 2)
    #expect(!m.hasUnclosedString)
  }

  // MARK: - Quote counting + escapes

  @Test func escapedQuoteInsideStringDoesNotToggle() {
    // {"a":"he\"llo"} — the `\"` is content, not a closing quote.
    let m = StringStateMachine(#"{"a":"he\"llo"}"#)
    #expect(m.unescapedQuoteCount == 4)
    #expect(!m.hasUnclosedString)
    #expect(m.braceBalance == 0)
  }

  @Test func escapedBackslashThenQuoteClosesString() {
    // {"a":"x\\"} — `\\` consumes the backslash, the next `"` is a real close.
    let m = StringStateMachine(#"{"a":"x\\"}"#)
    #expect(m.unescapedQuoteCount == 4)
    #expect(!m.hasUnclosedString)
    #expect(m.braceBalance == 0)
  }

  @Test func unicodeEscapeIsConsumedAsSingleToken() {
    // {"a":"é"} — 4 hex digits after \u must not toggle string state.
    let m = StringStateMachine(#"{"a":"é"}"#)
    #expect(m.unescapedQuoteCount == 4)
    #expect(!m.hasUnclosedString)
  }

  // MARK: - Unclosed string detection

  @Test func unclosedStringAtEndIsDetected() {
    let m = StringStateMachine(#"{"a":"hello"#)
    #expect(m.unescapedQuoteCount == 3)  // odd → unclosed
    #expect(m.hasUnclosedString)
    #expect(m.braceBalance == 1)  // outer `{` not yet closed
  }

  // MARK: - String-context awareness for braces / commas

  @Test func bracesInsideStringDoNotCountTowardBalance() {
    // The `{` and `}` inside the value are content, not structure.
    let m = StringStateMachine(#"{"a":"{nested}"}"#)
    #expect(m.braceBalance == 0)
  }

  @Test func bracketsInsideStringDoNotCountTowardBalance() {
    let m = StringStateMachine(#"{"a":"[nested]"}"#)
    #expect(m.bracketBalance == 0)
    #expect(m.braceBalance == 0)
  }

  @Test func asciiCommaInsideStringIsFlaggedAsInsideString() {
    // {"a":"hello, world"} — the comma at index 9 is inside the string;
    // a trailing-comma repair must NOT remove it.
    let text = #"{"a":"hello, world"}"#
    let m = StringStateMachine(text)
    let commaOffset = text.distance(
      from: text.startIndex, to: text.firstIndex(of: ",") ?? text.endIndex)
    #expect(m.isInsideString(at: commaOffset))
  }

  // MARK: - Mixed nesting

  @Test func mixedNestingObjectsAndArraysBalance() {
    let m = StringStateMachine(#"{"a":[1,2],"b":{"c":3}}"#)
    #expect(m.braceBalance == 0)
    #expect(m.bracketBalance == 0)
    #expect(!m.hasUnclosedString)
  }
}
