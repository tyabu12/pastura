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
    let machine = StringStateMachine("")
    #expect(machine.unescapedQuoteCount == 0)
    #expect(machine.braceBalance == 0)
    #expect(machine.bracketBalance == 0)
    #expect(!machine.hasUnclosedString)
  }

  @Test func wellFormedObjectIsBalanced() {
    let machine = StringStateMachine(#"{"a": 1}"#)
    #expect(machine.braceBalance == 0)
    #expect(machine.unescapedQuoteCount == 2)
    #expect(!machine.hasUnclosedString)
  }

  // MARK: - Quote counting + escapes

  @Test func escapedQuoteInsideStringDoesNotToggle() {
    // {"a":"he\"llo"} — the `\"` is content, not a closing quote.
    let machine = StringStateMachine(#"{"a":"he\"llo"}"#)
    #expect(machine.unescapedQuoteCount == 4)
    #expect(!machine.hasUnclosedString)
    #expect(machine.braceBalance == 0)
  }

  @Test func escapedBackslashThenQuoteClosesString() {
    // {"a":"x\\"} — `\\` consumes the backslash, the next `"` is a real close.
    let machine = StringStateMachine(#"{"a":"x\\"}"#)
    #expect(machine.unescapedQuoteCount == 4)
    #expect(!machine.hasUnclosedString)
    #expect(machine.braceBalance == 0)
  }

  @Test func unicodeEscapeIsConsumedAsSingleToken() {
    // {"a":"é"} — 4 hex digits after \u must not toggle string state.
    let machine = StringStateMachine(#"{"a":"é"}"#)
    #expect(machine.unescapedQuoteCount == 4)
    #expect(!machine.hasUnclosedString)
  }

  // MARK: - Unclosed string detection

  @Test func unclosedStringAtEndIsDetected() {
    let machine = StringStateMachine(#"{"a":"hello"#)
    #expect(machine.unescapedQuoteCount == 3)  // odd → unclosed
    #expect(machine.hasUnclosedString)
    #expect(machine.braceBalance == 1)  // outer `{` not yet closed
  }

  // MARK: - String-context awareness for braces / commas

  @Test func bracesInsideStringDoNotCountTowardBalance() {
    // The `{` and `}` inside the value are content, not structure.
    let machine = StringStateMachine(#"{"a":"{nested}"}"#)
    #expect(machine.braceBalance == 0)
  }

  @Test func bracketsInsideStringDoNotCountTowardBalance() {
    let machine = StringStateMachine(#"{"a":"[nested]"}"#)
    #expect(machine.bracketBalance == 0)
    #expect(machine.braceBalance == 0)
  }

  @Test func asciiCommaInsideStringIsFlaggedAsInsideString() {
    // {"a":"hello, world"} — the comma at index 9 is inside the string;
    // a trailing-comma repair must NOT remove it.
    let text = #"{"a":"hello, world"}"#
    let machine = StringStateMachine(text)
    let commaOffset = text.distance(
      from: text.startIndex, to: text.firstIndex(of: ",") ?? text.endIndex)
    #expect(machine.isInsideString(at: commaOffset))
  }

  // MARK: - Mixed nesting

  @Test func mixedNestingObjectsAndArraysBalance() {
    let machine = StringStateMachine(#"{"a":[1,2],"b":{"c":3}}"#)
    #expect(machine.braceBalance == 0)
    #expect(machine.bracketBalance == 0)
    #expect(!machine.hasUnclosedString)
  }
}
