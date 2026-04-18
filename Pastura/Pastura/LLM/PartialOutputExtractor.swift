import Foundation

/// Best-effort snapshot of a single LLM inference's currently-emitted
/// fields, derived from a buffer of streamed text.
///
/// Produced by ``PartialOutputExtractor/extract(from:)`` during
/// incremental generation and consumed by the streaming `LLMCaller`
/// path to push UI updates. The final canonical parse (via
/// ``JSONResponseParser``) is still the source of truth on stream end;
/// the extractor's job is to stay *consistent* with that canonical
/// result — every partial primary must be a prefix of the final one.
nonisolated public struct PartialSnapshot: Sendable, Equatable {
  /// Currently-visible value of the first primary key present in the
  /// buffer (one of: statement, declaration, boke, action, vote). `nil`
  /// while the extractor is waiting for that key's opening quote.
  public let primary: String?

  /// Currently-visible value of `inner_thought`, or `nil` until its
  /// opening quote has arrived.
  public let thought: String?

  public static let empty = PartialSnapshot(primary: nil, thought: nil)

  public init(primary: String?, thought: String?) {
    self.primary = primary
    self.thought = thought
  }
}

/// Extracts best-effort `(primary, thought)` snapshots from partial LLM
/// output text. Stateless — each ``extract(from:)`` call parses the
/// entire buffer fresh.
///
/// Strategy:
/// 1. Strip closed Gemma / generic thinking tags.
/// 2. If an *unclosed* thinking tag is present, yield an empty snapshot
///    (the model is still reasoning; nothing is safe to display).
/// 3. Otherwise locate the first `{` and scan for top-level `"<key>":"..."`
///    pairs that correspond to known primary keys or ``thoughtKey``.
/// 4. Decode escape sequences inside string values; hold back incomplete
///    escapes (`\`, partial `\uXXXX`) so the UI never sees invalid
///    characters mid-type.
///
/// Top-level detection uses a cheap heuristic — a candidate `"<key>"` is
/// treated as a real key only when it is both followed by `:` and
/// preceded by `{` or `,` (ignoring whitespace). This rejects key-like
/// substrings that appear inside string values.
nonisolated public struct PartialOutputExtractor: Sendable {
  /// Recognised primary-output keys in the order they are checked.
  ///
  /// Ordered so that first-match-wins aligns with
  /// ``TurnOutput/primaryText(for:)``'s phase-specific preferences:
  /// - speak phases: `statement ?? declaration ?? boke`
  /// - choose phase: `action ?? declaration`
  /// - vote phase: `vote`
  ///
  /// By putting `action` before `declaration`, a `.choose`-phase
  /// buffer containing both keys reports `action` — matching the
  /// canonical parser. Speak phases don't typically carry `action`,
  /// so the earlier-in-list priority is harmless there.
  public static let primaryKeys = [
    "statement", "action", "declaration", "boke", "vote"
  ]
  public static let thoughtKey = "inner_thought"

  // Pre-compiled regexes for stripping closed thinking tags.
  private static let channelThinkingRegex = try? NSRegularExpression(
    pattern: #"<\|channel>thought\s*.*?<channel\|>"#,
    options: .dotMatchesLineSeparators)
  private static let thinkTagRegex = try? NSRegularExpression(
    pattern: #"<think>.*?</think>"#,
    options: .dotMatchesLineSeparators)

  public init() {}

  public func extract(from text: String) -> PartialSnapshot {
    let stripped = stripClosedThinkingTags(text)
    if hasUnclosedThinkingTag(stripped) {
      return .empty
    }
    guard let braceIdx = stripped.firstIndex(of: "{") else {
      return .empty
    }
    let jsonPart = String(stripped[braceIdx...])

    var primary: String?
    for key in Self.primaryKeys {
      if let value = extractTopLevelStringValue(forKey: key, in: jsonPart) {
        primary = value
        break
      }
    }
    let thought = extractTopLevelStringValue(
      forKey: Self.thoughtKey, in: jsonPart)

    return PartialSnapshot(primary: primary, thought: thought)
  }

  // MARK: - Thinking-tag handling

  private func stripClosedThinkingTags(_ text: String) -> String {
    var result = text
    if let regex = Self.channelThinkingRegex {
      let range = NSRange(result.startIndex..., in: result)
      result = regex.stringByReplacingMatches(
        in: result, range: range, withTemplate: "")
    }
    if let regex = Self.thinkTagRegex {
      let range = NSRange(result.startIndex..., in: result)
      result = regex.stringByReplacingMatches(
        in: result, range: range, withTemplate: "")
    }
    return result
  }

  /// After stripping closed tags, an opener that still appears means
  /// the model is still generating reasoning — emission must wait.
  private func hasUnclosedThinkingTag(_ text: String) -> Bool {
    text.contains("<|channel>") || text.contains("<think>")
  }

  // MARK: - Top-level key lookup

  /// Find a top-level `"<key>"` position in the JSON-ish buffer. Returns
  /// the index immediately after the closing quote of the key, or `nil`
  /// if no top-level occurrence is found.
  private func findTopLevelKey(
    _ key: String, in json: String
  ) -> String.Index? {
    let pattern = "\"\(key)\""
    var searchStart = json.startIndex
    while searchStart < json.endIndex {
      guard
        let range = json.range(
          of: pattern, range: searchStart..<json.endIndex)
      else {
        return nil
      }

      let followedByColon = isFollowedByColon(
        after: range.upperBound, in: json)
      let precededByOpener = isPrecededByOpener(
        before: range.lowerBound, in: json)

      if followedByColon && precededByOpener {
        return range.upperBound
      }
      searchStart = range.upperBound
    }
    return nil
  }

  private func isFollowedByColon(
    after idx: String.Index, in json: String
  ) -> Bool {
    var i = idx
    while i < json.endIndex, json[i].isWhitespace {
      i = json.index(after: i)
    }
    return i < json.endIndex && json[i] == ":"
  }

  private func isPrecededByOpener(
    before idx: String.Index, in json: String
  ) -> Bool {
    var i = idx
    while i > json.startIndex {
      i = json.index(before: i)
      let char = json[i]
      if !char.isWhitespace {
        return char == "{" || char == ","
      }
    }
    return false
  }

  // MARK: - String-value extraction

  /// Scan `"<key>"\s*:\s*"<decoded-value>"` at the top level. Returns:
  /// - `nil` if the key has not been observed yet at top level.
  /// - `nil` if the key exists but no value colon/opening-quote yet.
  /// - `""` once the opening quote is past but no content has arrived.
  /// - decoded partial content thereafter, holding back any incomplete
  ///   trailing escape.
  private func extractTopLevelStringValue(
    forKey targetKey: String, in json: String
  ) -> String? {
    guard let afterKey = findTopLevelKey(targetKey, in: json) else {
      return nil
    }

    var i = afterKey
    while i < json.endIndex, json[i].isWhitespace {
      i = json.index(after: i)
    }
    guard i < json.endIndex, json[i] == ":" else { return nil }
    i = json.index(after: i)
    while i < json.endIndex, json[i].isWhitespace {
      i = json.index(after: i)
    }
    guard i < json.endIndex, json[i] == "\"" else { return nil }
    i = json.index(after: i)

    return decodeStringContent(startingAt: i, in: json)
  }

  /// Decode JSON string content up to the first unescaped `"` or the
  /// end of buffer. Holds back incomplete trailing escapes so the UI
  /// never renders a lone backslash or a partial `\uXXXX`.
  private func decodeStringContent(  // swiftlint:disable:this cyclomatic_complexity
    startingAt start: String.Index, in json: String
  ) -> String {
    var decoded = ""
    var i = start
    while i < json.endIndex {
      let char = json[i]
      if char == "\"" {
        return decoded
      }
      if char == "\\" {
        let next = json.index(after: i)
        guard next < json.endIndex else { return decoded }
        let escChar = json[next]
        switch escChar {
        case "\"": decoded.append("\"")
        case "\\": decoded.append("\\")
        case "/": decoded.append("/")
        case "n": decoded.append("\n")
        case "t": decoded.append("\t")
        case "r": decoded.append("\r")
        case "b": decoded.append("\u{08}")
        case "f": decoded.append("\u{0C}")
        case "u":
          let hexStart = json.index(after: next)
          guard
            let hexEnd = json.index(
              hexStart, offsetBy: 4, limitedBy: json.endIndex)
          else {
            return decoded
          }
          let hex = String(json[hexStart..<hexEnd])
          guard let code = UInt32(hex, radix: 16),
            let scalar = Unicode.Scalar(code)
          else {
            return decoded
          }
          decoded.append(Character(scalar))
          i = hexEnd
          continue
        default:
          // Unknown escape — preserve both chars verbatim so the final
          // canonical parse remains authoritative on meaning.
          decoded.append(char)
          decoded.append(escChar)
        }
        i = json.index(after: next)
        continue
      }
      decoded.append(char)
      i = json.index(after: i)
    }
    return decoded
  }
}
