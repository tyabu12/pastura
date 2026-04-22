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
  /// Thin wrapper over ``parse(_:expectedKeys:)`` with no schema-aware
  /// repair guard. Existing callers that don't have ``Phase/outputSchema``
  /// in scope (most tests, replay paths) keep the same `TurnOutput`-only
  /// return shape.
  ///
  /// - Parameter text: The raw text response from the LLM.
  /// - Returns: A ``TurnOutput`` with all values normalized to `String`.
  /// - Throws: ``LLMError/invalidResponse(raw:)`` if no valid JSON can be extracted.
  public func parse(_ text: String) throws -> TurnOutput {
    let (output, _) = try parse(text, expectedKeys: [])
    return output
  }

  /// Parse with optional schema-aware repair guard.
  ///
  /// Processing pipeline:
  /// 1. Strip thinking tags (`<think>...`, `<|channel>thought...`)
  /// 2. Truncate at chat template tokens (`<|im_end|>`)
  /// 3. Extract content from markdown code blocks
  /// 4. Find first `{...}` JSON object
  /// 5. Try `JSONSerialization` on the cleaned text
  /// 6. On failure: apply repair pipeline (`unclosed_string` →
  ///    `trailing_comma` → `unclosed_brace`), retry parse, and reject
  ///    the result if `expectedKeys` are not all present and non-empty
  ///
  /// Repairs are sequenced unclosed-string-first because closing the
  /// string changes the brace balance computation; trailing-comma strip
  /// runs before brace-close because it can yield a clean parse without
  /// needing closer insertion.
  ///
  /// When `expectedKeys` is non-empty, a repair that produces parseable
  /// JSON missing any of those keys is rejected — preserves the original
  /// throw rather than fabricating a `TurnOutput` (#194 PR#a Item 2d).
  ///
  /// - Returns: tuple of the parsed ``TurnOutput`` plus the applied repair
  ///   kind (`"trailing_comma"` / `"unclosed_string"` / `"unclosed_brace"`,
  ///   or `+`-joined for composites). `nil` repair kind means the input
  ///   parsed cleanly without any repair.
  /// - Throws: ``LLMError/invalidResponse(raw:)`` when no repair attempt
  ///   yields parseable JSON satisfying the schema guard.
  public func parse(
    _ text: String, expectedKeys: Set<String>
  ) throws -> (TurnOutput, repairKind: String?) {
    let cleaned = applyCleanupPipeline(text)

    // Try as-is — happy path, no repair needed.
    if let output = tryParse(cleaned, originalText: text) {
      return (output, nil)
    }

    // Repair pipeline. Each repair operates on the *current* repaired text
    // and recomputes its `StringStateMachine` because earlier repairs
    // change positions. Multiple may apply in one pass (e.g. an unclosed
    // string at end-of-input that also leaves a brace open).
    var repaired = cleaned
    var appliedKinds: [String] = []

    let m1 = StringStateMachine(repaired)
    if m1.hasUnclosedString {
      // Refuse to repair mid-key truncation (`{"a":"v1","action`) — only
      // close strings that are in value position. Returning nil from the
      // helper preserves the original throw via the guard below.
      guard let closed = closeUnclosedLastString(repaired, machine: m1) else {
        throw LLMError.invalidResponse(raw: text)
      }
      repaired = closed
      appliedKinds.append("unclosed_string")
    }

    // Note: a dedicated trailing-comma repair was prototyped but turned
    // out to be a no-op on Apple platforms — `JSONSerialization.jsonObject`
    // accepts trailing commas in objects and arrays (`{"a":1,}` /
    // `[1,2,]`) by default on iOS 17+. The brace-close repair below
    // strips a single dangling `,`/`:` at end-of-input as part of its
    // own work, which covers the only remaining trailing-comma case
    // (truncated stream ending with `,`).

    let m2 = StringStateMachine(repaired)
    if m2.braceBalance > 0 || m2.bracketBalance > 0 {
      repaired = closeUnclosedBraces(repaired, machine: m2)
      appliedKinds.append("unclosed_brace")
    }

    guard !appliedKinds.isEmpty,
      let output = tryParse(repaired, originalText: text)
    else {
      throw LLMError.invalidResponse(raw: text)
    }

    // Schema-aware guard — reject repairs that drop or empty required keys.
    // Non-empty `expectedKeys` typically comes from `phase.outputSchema?.keys`
    // at the handler call site (passed via `LLMCaller`).
    if !expectedKeys.isEmpty {
      let allPresent = expectedKeys.allSatisfy { key in
        guard let value = output.fields[key], !value.isEmpty else { return false }
        return true
      }
      guard allPresent else {
        throw LLMError.invalidResponse(raw: text)
      }
    }

    return (output, appliedKinds.joined(separator: "+"))
  }

  // MARK: - Internal helpers

  private func applyCleanupPipeline(_ text: String) -> String {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned = stripThinkingTags(cleaned)
    cleaned = truncateAtChatTemplateToken(cleaned)
    cleaned = extractFromCodeBlock(cleaned)
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleaned.hasPrefix("{") || !cleaned.hasSuffix("}") {
      cleaned = extractFirstJSONObject(cleaned)
    }
    return cleaned
  }

  private func tryParse(_ cleaned: String, originalText: String) -> TurnOutput? {
    guard let data = cleaned.data(using: .utf8),
      let jsonObject = try? JSONSerialization.jsonObject(with: data),
      let dictionary = jsonObject as? [String: Any]
    else {
      return nil
    }
    let fields = normalizeValues(dictionary)
    // Preserve the ORIGINAL pre-cleanup input so it can flow through to
    // `TurnRecord.rawOutput` for audit. See #194.
    return TurnOutput(fields: fields, rawText: originalText)
  }

  // MARK: - Repair primitives (#194 PR#a Item 2c)

  /// Append a `"` to close an unclosed string at end-of-input — but
  /// only when the unclosed string is in *value position* (i.e. preceded
  /// by `:` after whitespace skip). Mid-key truncations like
  /// `{"a":"v1","action` have an even quote count (no unclosed string)
  /// and are not reached here; this guard catches the rarer case of a
  /// genuinely-unclosed string opened by a non-value position.
  private func closeUnclosedLastString(
    _ text: String, machine: StringStateMachine
  ) -> String? {
    let chars = Array(text)
    // Find the last opening quote (a `"` whose flag at that index is
    // `false`, meaning it transitions outside → inString).
    var lastOpenIndex = -1
    for i in 0..<chars.count where chars[i] == "\"" && !machine.isInsideString(at: i) {
      lastOpenIndex = i
    }
    guard lastOpenIndex >= 0 else { return nil }
    // Check value-position: char immediately before the opener (skipping
    // whitespace) must be `:`.
    var k = lastOpenIndex - 1
    while k >= 0, chars[k].isWhitespace { k -= 1 }
    guard k >= 0, chars[k] == ":" else { return nil }
    return text + "\""
  }

  /// (c) Append closing braces / brackets to bring balance to zero, after
  /// stripping a single dangling `,` or `:` at the very end (outside
  /// string context).
  ///
  /// Limitation: brackets are appended before braces, which is correct
  /// for object-rooted JSON (Pastura's output schema is always an object
  /// at root). Array-rooted inputs with mixed nesting like `[{"a":1`
  /// would close in the wrong order — not reachable from current usage.
  private func closeUnclosedBraces(
    _ text: String, machine: StringStateMachine
  ) -> String {
    var stripped = text
    if let last = stripped.last,
      last == "," || last == ":",
      !machine.isInsideString(at: stripped.count - 1) {
      stripped.removeLast()
    }
    let m = StringStateMachine(stripped)
    var result = stripped
    if m.bracketBalance > 0 {
      result += String(repeating: "]", count: m.bracketBalance)
    }
    if m.braceBalance > 0 {
      result += String(repeating: "}", count: m.braceBalance)
    }
    return result
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
