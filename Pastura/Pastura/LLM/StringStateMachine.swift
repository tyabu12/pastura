import Foundation

/// JSON string-literal state tracker used by ``JSONResponseParser`` repair
/// heuristics (#194 PR#a Item 2).
///
/// Walks the input once and records, for every character offset, whether
/// that character is inside a JSON string literal (string-context-aware)
/// — plus aggregate counts of unescaped quotes and structural brace /
/// bracket balance computed only over chars *outside* string context.
///
/// The repair heuristics rely on this primitive to avoid false positives:
/// - A `,` inside a Japanese string value (`{"statement":"はい、そうです"}`)
///   must not register as a trailing comma.
/// - A `}` inside a string value (`{"statement":"答えは{\"a\":1}"}`) must
///   not count against the brace balance when deciding how many closers
///   to append.
///
/// JSON escape semantics modelled:
/// - `\"` — literal quote, does not toggle string state
/// - `\\` — literal backslash, the following char (including `"`) is
///   processed normally
/// - `\uXXXX` — 4-hex-digit unicode escape, all 4 hex chars are consumed
///   without state changes
/// - Other one-char escapes (`\n`, `\t`, `\/`, …) — the escaped char is
///   consumed without state changes
nonisolated struct StringStateMachine {
  /// True at offset `i` iff character at offset `i` is inside a string
  /// literal (the surrounding `"` characters are *not* themselves inside).
  /// Length equals `text.count`.
  let insideStringFlags: [Bool]

  /// Count of unescaped `"` characters. An odd value means the input
  /// ends mid-string (one quote opened, never closed).
  let unescapedQuoteCount: Int

  /// `{` count minus `}` count over chars outside string context.
  /// Positive means more openers than closers (need closing braces).
  let braceBalance: Int

  /// `[` count minus `]` count over chars outside string context.
  let bracketBalance: Int

  var hasUnclosedString: Bool { !unescapedQuoteCount.isMultiple(of: 2) }

  init(_ text: String) {
    var flags: [Bool] = []
    flags.reserveCapacity(text.count)
    var state: State = .outside
    var quoteCount = 0
    var braces = 0
    var brackets = 0

    for char in text {
      // Record whether THIS character is inside a string literal — the
      // opening `"` itself is not inside (state == .outside until processed);
      // the closing `"` likewise (state == .inString until processed and
      // toggled back to .outside).
      flags.append(state.isInsideString)
      state = Self.advance(
        state: state,
        char: char,
        quoteCount: &quoteCount,
        braces: &braces,
        brackets: &brackets)
    }

    self.insideStringFlags = flags
    self.unescapedQuoteCount = quoteCount
    self.braceBalance = braces
    self.bracketBalance = brackets
  }

  /// One step of the string-literal state machine. Updates structural
  /// counters in-place; returns the next state. Extracted from `init`
  /// to keep the per-`char` loop body small (lint budget).
  private static func advance(
    state: State,
    char: Character,
    quoteCount: inout Int,
    braces: inout Int,
    brackets: inout Int
  ) -> State {
    switch state {
    case .outside:
      return advanceFromOutside(
        char: char, quoteCount: &quoteCount,
        braces: &braces, brackets: &brackets)
    case .inString:
      return advanceFromInString(char: char, quoteCount: &quoteCount)
    case .afterEscape:
      // `\u` enters a 4-hex-digit consumption. Any other escape (`\"`,
      // `\\`, `\n`, …) is a single-char skip — return to .inString.
      return char == "u" ? .afterUnicode(remaining: 4) : .inString
    case .afterUnicode(let remaining):
      return remaining <= 1 ? .inString : .afterUnicode(remaining: remaining - 1)
    }
  }

  private static func advanceFromOutside(
    char: Character,
    quoteCount: inout Int,
    braces: inout Int,
    brackets: inout Int
  ) -> State {
    switch char {
    case "\"":
      quoteCount += 1
      return .inString
    case "{":
      braces += 1
    case "}":
      braces -= 1
    case "[":
      brackets += 1
    case "]":
      brackets -= 1
    default:
      break
    }
    return .outside
  }

  private static func advanceFromInString(
    char: Character, quoteCount: inout Int
  ) -> State {
    if char == "\"" {
      quoteCount += 1
      return .outside
    }
    if char == "\\" {
      return .afterEscape
    }
    return .inString
  }

  /// True iff character at `offset` (Character index, 0-based) is inside a
  /// JSON string literal. Returns `false` for out-of-range offsets.
  func isInsideString(at offset: Int) -> Bool {
    guard offset >= 0, offset < insideStringFlags.count else { return false }
    return insideStringFlags[offset]
  }

  private enum State {
    case outside
    case inString
    case afterEscape
    case afterUnicode(remaining: Int)

    var isInsideString: Bool {
      switch self {
      case .outside: return false
      case .inString, .afterEscape, .afterUnicode: return true
      }
    }
  }
}
