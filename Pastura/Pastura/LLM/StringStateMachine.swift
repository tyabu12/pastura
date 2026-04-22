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
      // Record whether THIS character is inside a string literal.
      // The opening `"` itself is not inside (state == .outside until
      // it's processed); the closing `"` likewise (state == .inString
      // until it's processed and toggles back to .outside).
      let inside: Bool
      switch state {
      case .outside:
        inside = false
      case .inString, .afterEscape, .afterUnicode:
        inside = true
      }
      flags.append(inside)

      switch state {
      case .outside:
        if char == "\"" {
          state = .inString
          quoteCount += 1
        } else if char == "{" {
          braces += 1
        } else if char == "}" {
          braces -= 1
        } else if char == "[" {
          brackets += 1
        } else if char == "]" {
          brackets -= 1
        }
      // Other chars outside strings are insignificant for repair purposes.
      case .inString:
        if char == "\"" {
          state = .outside
          quoteCount += 1
        } else if char == "\\" {
          state = .afterEscape
        }
      case .afterEscape:
        // `\u` enters a 4-hex-digit consumption. Any other escape (`\"`,
        // `\\`, `\n`, …) is a single-char skip — return to .inString.
        if char == "u" {
          state = .afterUnicode(remaining: 4)
        } else {
          state = .inString
        }
      case .afterUnicode(let remaining):
        if remaining <= 1 {
          state = .inString
        } else {
          state = .afterUnicode(remaining: remaining - 1)
        }
      }
    }

    self.insideStringFlags = flags
    self.unescapedQuoteCount = quoteCount
    self.braceBalance = braces
    self.bracketBalance = brackets
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
  }
}
