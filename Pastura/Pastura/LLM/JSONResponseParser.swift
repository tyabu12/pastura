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
  // ChatML-only by construction: correct for Qwen 3; for Gemma 4, whose
  // markers are `<|turn>` / `<turn|>`, it can only fire on a spelled-out
  // `<|im_end|>` — see the doc on `truncateAtChatTemplateToken`.
  // Making this per-model is #1422; the false-rationale half was #1417.
  private static let chatTemplateTokenRegex = try? NSRegularExpression(
    pattern: #"<\|im_end\|>.*"#,
    options: .dotMatchesLineSeparators
  )
  private static let codeBlockRegex = try? NSRegularExpression(
    pattern: #"```(?:json)?\s*\n?(.*?)\n?```"#,
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
  /// 2. Truncate at ChatML chat-template tokens (`<|im_end|>`; for a
  ///    non-ChatML model such as Gemma 4 this matches nothing it emits — #1422)
  /// 3. Extract content from markdown code blocks
  /// 4. Extract the first balanced `{...}` object (string-aware), discarding
  ///    any trailing content after its matching close brace
  /// 5. Try `JSONSerialization` on the cleaned text
  /// 6. On failure with non-empty `expectedKeys`: attempt schema-guarded
  ///    multi-object salvage (see below) before the repair pipeline
  /// 7. On failure: two-step repair (`unclosed_string` → `unclosed_brace`),
  ///    retry parse, reject if `expectedKeys` not all present + non-empty
  ///
  /// Schema-guarded multi-object salvage (#907): on happy-path failure with a
  /// non-empty schema, the first balanced object is re-extracted ignoring the
  /// #751 object-like-residue refusal and accepted only with ALL `expectedKeys`
  /// present and non-empty (see `extractFirstJSONObject`'s `allowObjectResidue`).
  /// The schema-less path keeps the #751 refusal verbatim; single-field
  /// grammars made the multi-object shape dominant, so retrying cannot converge.
  ///
  /// Repair order rationale: unclosed-string runs first because closing
  /// the string changes the subsequent brace-balance computation.
  /// Brace-close also strips a single dangling `,`/`:` at end-of-input
  /// as part of its own housekeeping — that covers the only trailing-
  /// comma case reachable here, because `JSONSerialization.jsonObject`
  /// on iOS 17+ already accepts `{"a":1,}` / `[1,2,]` in step 5 without
  /// needing a dedicated repair.
  ///
  /// When `expectedKeys` is non-empty, a repair that produces parseable
  /// JSON missing any of those keys is rejected — preserves the original
  /// throw rather than fabricating a `TurnOutput` (#194 PR#a Item 2d).
  ///
  /// - Returns: tuple of the parsed ``TurnOutput`` plus the applied repair
  ///   kind (`"unclosed_string"` / `"unclosed_brace"`, or `+`-joined for
  ///   the composite). `nil` repair kind means the input parsed cleanly
  ///   without any repair.
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

    // Schema-guarded multi-object salvage (#907) — recovers a complete-but-
    // followed-by-junk first object before the repair pipeline runs.
    if !expectedKeys.isEmpty {
      let salvaged = applyCleanupPipeline(text, allowObjectResidue: true)
      if let output = tryParse(salvaged, originalText: text),
        hasAllExpectedKeys(output, expectedKeys: expectedKeys) {
        return (output, "multi_object_salvage")
      }
    }

    // Repair pipeline. Each repair operates on the *current* repaired text
    // and recomputes its `StringStateMachine` because earlier repairs
    // change positions. Multiple may apply in one pass (e.g. an unclosed
    // string at end-of-input that also leaves a brace open).
    var repaired = cleaned
    var appliedKinds: [String] = []

    let stringScan = StringStateMachine(repaired)
    if stringScan.hasUnclosedString {
      // Refuse to repair mid-key truncation (`{"a":"v1","action`) — only
      // close strings that are in value position. Returning nil from the
      // helper preserves the original throw via the guard below.
      guard let closed = closeUnclosedLastString(repaired, machine: stringScan) else {
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

    let braceScan = StringStateMachine(repaired)
    if braceScan.braceBalance > 0 || braceScan.bracketBalance > 0 {
      repaired = closeUnclosedBraces(repaired, machine: braceScan)
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
      guard hasAllExpectedKeys(output, expectedKeys: expectedKeys) else {
        throw LLMError.invalidResponse(raw: text)
      }
    }

    return (output, appliedKinds.joined(separator: "+"))
  }

  // MARK: - Internal helpers

  /// True when every `expectedKeys` entry is present with a non-empty value.
  private func hasAllExpectedKeys(
    _ output: TurnOutput, expectedKeys: Set<String>
  ) -> Bool {
    expectedKeys.allSatisfy { key in
      guard let value = output.fields[key], !value.isEmpty else { return false }
      return true
    }
  }

  private func applyCleanupPipeline(
    _ text: String, allowObjectResidue: Bool = false
  ) -> String {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned = stripThinkingTags(cleaned)
    cleaned = truncateAtChatTemplateToken(cleaned)
    cleaned = extractFromCodeBlock(cleaned)
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    // Always extract: a `{`/`}`-framed string is NOT proof of a clean single
    // object. Grammar-constrained generation can append a stray `}` (`{…}}`,
    // #751 sub-class 1) or trailing prose after the real close — both pass a
    // prefix/suffix check yet break `JSONSerialization`. The balanced scan is
    // an identity transform for an already-clean object; for trailing garbage
    // it trims back to the first complete object, and for an object-like
    // trailing residue (`{…}{…}`) it returns the input unchanged so the
    // multi-object span throws (see `extractFirstJSONObject`, #751 hybrid) —
    // UNLESS `allowObjectResidue` is set for the schema-guarded salvage path
    // (#907), which salvages the first object instead.
    cleaned = extractFirstJSONObject(cleaned, allowObjectResidue: allowObjectResidue)
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
    var prev = lastOpenIndex - 1
    while prev >= 0, chars[prev].isWhitespace { prev -= 1 }
    guard prev >= 0, chars[prev] == ":" else { return nil }
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
    let recomputed = StringStateMachine(stripped)
    var result = stripped
    if recomputed.bracketBalance > 0 {
      result += String(repeating: "]", count: recomputed.bracketBalance)
    }
    if recomputed.braceBalance > 0 {
      result += String(repeating: "}", count: recomputed.braceBalance)
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

  /// Truncate at the first ChatML chat-template token (`<|im_end|>`).
  ///
  /// When a **ChatML** model hallucinates past its own turn it emits
  /// `<|im_end|>` as text, followed by fabricated user/assistant turns.
  /// Discarding everything from the first such token prevents the greedy JSON
  /// regex from capturing content across hallucinated turns.
  ///
  /// - Important: the token is hardcoded, so for a non-ChatML model this step
  ///   fires only on a spelled-out `<|im_end|>`. Gemma 4's markers are
  ///   `<|turn>` / `<turn|>` and `<|im_end|>` is not in its vocabulary, so
  ///   spelled-out is the only form that could arrive — and it is not the form
  ///   a Gemma hallucination would reach for. What this step does NOT do for
  ///   Gemma is truncate a Gemma-shaped continuation.
  ///
  ///   This type is backend-agnostic (`LLMCaller` parses llama.cpp, Ollama and
  ///   Foundation Models output through one instance), so do not assume the
  ///   llama.cpp guarantee here: under *that* backend a control marker cannot
  ///   reach decoded text at all (see the canonical note on
  ///   `LlamaCppService.stopSequence`), but a server-decoding backend offers no
  ///   such guarantee — cf. `LLMCaller.logChatTemplateLeakage`, which exists
  ///   because those backends can still emit template tokens.
  ///
  ///   **Which text a Gemma hallucination would spell out is not
  ///   established**; whatever it is, it would not be truncated here.
  ///   Sourcing the marker per-model is tracked in #1422.
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

  /// Extract the first balanced `{...}` JSON object, string-aware.
  ///
  /// Walks from the first structural `{` (outside any string literal),
  /// tracking brace balance over characters outside string context via
  /// ``StringStateMachine``, and returns the slice ending at the `}` that
  /// brings balance back to zero. A greedy `#"\{.*\}"#` regex (the prior
  /// implementation) would instead run to the *last* `}` in the text; the
  /// balanced scan stops at the *first* matching close.
  ///
  /// Trailing content after that close is treated by its severity (#751
  /// hybrid):
  /// - A stray `}` (`{…}}`, #751 sub-class 1) or trailing prose is a benign
  ///   boundary artifact (the object content completed before it) — discard
  ///   it and keep the complete first object.
  /// - A trailing **object-like** residue (`{…}{…}`, the post-close text
  ///   starts with `{`) signals the generation re-rolled a whole second
  ///   answer. By default (schema-less path) return the input unchanged so
  ///   `JSONSerialization` rejects the multi-object span → re-try for a
  ///   cleaner sample, rather than salvaging a possibly off-persona first
  ///   object. `allowObjectResidue` overrides that: the first object is
  ///   salvaged anyway. Only the schema-guarded salvage path
  ///   (`parse(_:expectedKeys:)`, #907) passes `true`, and it additionally
  ///   requires all expected keys with content.
  ///
  /// Also returns the input unchanged when no `{` exists or the braces never
  /// balance (unclosed object) so the downstream repair pipeline
  /// (`closeUnclosedBraces`) can still fire.
  private func extractFirstJSONObject(
    _ text: String, allowObjectResidue: Bool = false
  ) -> String {
    let chars = Array(text)
    let machine = StringStateMachine(text)
    guard
      let start = chars.indices.first(where: {
        chars[$0] == "{" && !machine.isInsideString(at: $0)
      })
    else {
      return text
    }

    var balance = 0
    for i in start..<chars.count where !machine.isInsideString(at: i) {
      switch chars[i] {
      case "{":
        balance += 1
      case "}":
        balance -= 1
        if balance == 0 {
          // Object-like trailing residue → defer to multi-object throw,
          // unless the schema-guarded salvage path opts in (#907).
          let residue = chars[(i + 1)...].drop(while: { $0.isWhitespace })
          if residue.first == "{" && !allowObjectResidue {
            return text
          }
          return String(chars[start...i])
        }
      default:
        break
      }
    }
    // Unclosed — let the repair pipeline handle it.
    return text
  }
}
