import Foundation

/// Extracts structured data from raw LLM text responses.
///
/// Handles common LLM output artifacts: thinking tags
/// (`<think>`, `<|channel>thought`), markdown code blocks,
/// and leading/trailing garbage text.
/// All JSON values are normalized to `String` for ``TurnOutput``.
nonisolated public struct JSONResponseParser: Sendable {
  // Pre-compiled regexes for performance across many parse calls
  // TODO: Add assertionFailure in #if DEBUG for nil cases — these are compile-time
  // constants that should never fail, but silent nil degrades parsing without warning.
  // Gemma 4 channel thinking: `<|channel>thought...<channel|>` (newline optional)
  private static let channelThinkingRegex = try? NSRegularExpression(
    pattern: #"<\|channel>thought\s*.*?<channel\|>"#,
    options: .dotMatchesLineSeparators
  )
  // Common thinking model format: `<think>...</think>` (DeepSeek, Qwen, etc.)
  private static let thinkTagRegex = try? NSRegularExpression(
    pattern: #"<think>.*?</think>"#,
    options: .dotMatchesLineSeparators
  )
  // Chat template tokens — truncate everything from first occurrence onwards.
  // Catches hallucinated continuations where the model generates past its own turn.
  private static let chatTemplateTokenRegex = try? NSRegularExpression(
    pattern: #"<\|im_end\|>.*"#,
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
  /// 1. Strip thinking tags (`<think>...`, `<|channel>thought...`)
  /// 2. Truncate at chat template tokens (`<|im_end|>`)
  /// 3. Extract content from markdown code blocks
  /// 4. Find first `{...}` JSON object
  /// 5. Parse JSON and normalize all values to `String`
  ///
  /// - Parameter text: The raw text response from the LLM.
  /// - Returns: A ``TurnOutput`` with all values normalized to `String`.
  /// - Throws: ``LLMError/invalidResponse(raw:)`` if no valid JSON can be extracted.
  public func parse(_ text: String) throws -> TurnOutput {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // 1. Strip thinking tags
    cleaned = stripThinkingTags(cleaned)

    // 2. Truncate at chat template tokens (e.g. <|im_end|>) to discard
    //    hallucinated conversation continuations
    cleaned = truncateAtChatTemplateToken(cleaned)

    // 3. Extract from code blocks
    cleaned = extractFromCodeBlock(cleaned)

    // 4. Find first JSON object (also handles trailing garbage)
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleaned.hasPrefix("{") || !cleaned.hasSuffix("}") {
      cleaned = extractFirstJSONObject(cleaned)
    }

    // 5. Parse and normalize
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

  /// Remove thinking tags from LLM output.
  ///
  /// Handles two formats:
  /// - Gemma 4 channel: `<|channel>thought...<channel|>`
  /// - Common think tags: `<think>...</think>`
  private func stripThinkingTags(_ text: String) -> String {
    var result = text

    if let regex = Self.channelThinkingRegex {
      let range = NSRange(result.startIndex..., in: result)
      result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
    }
    if let regex = Self.thinkTagRegex {
      let range = NSRange(result.startIndex..., in: result)
      result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
    }

    return result
  }

  /// Truncate at the first chat template token (`<|im_end|>`).
  ///
  /// When the model hallucinates past its own turn, it emits `<|im_end|>`
  /// followed by fabricated user/assistant turns. Discarding everything from
  /// the first such token prevents the greedy JSON regex from capturing
  /// content across hallucinated turns.
  private func truncateAtChatTemplateToken(_ text: String) -> String {
    guard let regex = Self.chatTemplateTokenRegex else { return text }
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
