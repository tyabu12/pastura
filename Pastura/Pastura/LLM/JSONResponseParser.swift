import Foundation

/// Extracts structured data from raw LLM text responses.
///
/// Handles common LLM output artifacts: Gemma 4 thinking tags,
/// markdown code blocks, and leading/trailing garbage text.
/// All JSON values are normalized to `String` for ``TurnOutput``.
nonisolated public struct JSONResponseParser: Sendable {
  // Pre-compiled regexes for performance across many parse calls
  private static let thinkingTagRegex = try? NSRegularExpression(
    pattern: #"<\|channel>thought\n.*?<channel\|>"#,
    options: .dotMatchesLineSeparators
  )
  private static let codeBlockRegex = try? NSRegularExpression(
    pattern: #"```(?:json)?\s*\n?(.*?)\n?```"#,
    options: .dotMatchesLineSeparators
  )
  private static let jsonObjectRegex = try? NSRegularExpression(
    pattern: #"\{.*\}"#,
    options: .dotMatchesLineSeparators
  )

  public init() {}

  /// Parse raw LLM output text into a ``TurnOutput``.
  ///
  /// Processing pipeline:
  /// 1. Strip Gemma 4 thinking tags (`<|channel>thought...`)
  /// 2. Extract content from markdown code blocks
  /// 3. Find first `{...}` JSON object
  /// 4. Parse JSON and normalize all values to `String`
  ///
  /// - Parameter text: The raw text response from the LLM.
  /// - Returns: A ``TurnOutput`` with all values normalized to `String`.
  /// - Throws: ``LLMError/invalidResponse(raw:)`` if no valid JSON can be extracted.
  public func parse(_ text: String) throws -> TurnOutput {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // 1. Strip Gemma 4 thinking tags
    cleaned = stripThinkingTags(cleaned)

    // 2. Extract from code blocks
    cleaned = extractFromCodeBlock(cleaned)

    // 3. Find first JSON object
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleaned.hasPrefix("{") {
      cleaned = extractFirstJSONObject(cleaned)
    }

    // 4. Parse and normalize
    guard let data = cleaned.data(using: .utf8),
      let jsonObject = try? JSONSerialization.jsonObject(with: data),
      let dictionary = jsonObject as? [String: Any]
    else {
      throw LLMError.invalidResponse(raw: text)
    }

    let fields = normalizeValues(dictionary)
    return TurnOutput(fields: fields)
  }

  // MARK: - Pipeline Steps

  /// Remove Gemma 4 thinking tags: `<|channel>thought\n...<channel|>`
  private func stripThinkingTags(_ text: String) -> String {
    guard let regex = Self.thinkingTagRegex else { return text }
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
  }

  /// Extract content from markdown code blocks: `` ```json ... ``` `` or `` ``` ... ``` ``
  private func extractFromCodeBlock(_ text: String) -> String {
    guard text.contains("```"), let regex = Self.codeBlockRegex else { return text }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let contentRange = Range(match.range(at: 1), in: text)
    else {
      return text
    }

    return String(text[contentRange])
  }

  /// Find the first `{...}` JSON object in text with leading garbage.
  private func extractFirstJSONObject(_ text: String) -> String {
    guard let regex = Self.jsonObjectRegex else { return text }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let matchRange = Range(match.range, in: text)
    else {
      return text
    }

    return String(text[matchRange])
  }

  /// Normalize all JSON values to `String`. Null values are omitted.
  private func normalizeValues(_ dictionary: [String: Any]) -> [String: String] {
    var result: [String: String] = [:]
    for (key, value) in dictionary {
      if value is NSNull {
        // Null values are omitted
        continue
      } else if let stringValue = value as? String {
        result[key] = stringValue
      } else if let boolValue = value as? Bool {
        // Check Bool before NSNumber — Bool bridges to NSNumber in ObjC
        result[key] = boolValue ? "true" : "false"
      } else if let numberValue = value as? NSNumber {
        result[key] = numberValue.stringValue
      } else if JSONSerialization.isValidJSONObject(value) {
        // Nested object or array → serialize back to JSON string
        if let jsonData = try? JSONSerialization.data(
          withJSONObject: value, options: [.sortedKeys]),
          let jsonString = String(data: jsonData, encoding: .utf8) {
          result[key] = jsonString
        }
      }
    }
    return result
  }
}
