import Foundation

/// Value normalization — the final step of ``JSONResponseParser/parse(_:)``.
///
/// Split out of `JSONResponseParser.swift`, which sits at the 400-line
/// `file_length` cap.
///
/// `nonisolated` on the extension is load-bearing — verified, not assumed:
/// dropping it fails the build with `call to main actor-isolated instance
/// method 'normalizeValues' in a synchronous nonisolated context` at the
/// `tryParse` callsite. Methods in a plain `extension` inherit MainActor under
/// the project's default-actor-isolation setting (`.claude/rules/swift-isolation.md`
/// Pattern 3). Most `LlamaCppService+*.swift` siblings here need no annotation
/// because their callers are `async`; this one is reached synchronously.
nonisolated extension JSONResponseParser {
  /// Normalize all JSON values to `String`. Null values are omitted.
  ///
  /// Internal rather than `private` only because a sibling-file extension
  /// cannot expose a `private` member to the declaring file's callers.
  func normalizeValues(_ dictionary: [String: Any]) -> [String: String] {
    var result: [String: String] = [:]
    for (key, value) in dictionary {
      if value is NSNull {
        // Null values are omitted
        continue
      } else if let stringValue = value as? String {
        result[key] = stringValue
      } else if let numberValue = value as? NSNumber {
        // `as? Bool` cannot discriminate here: NSNumber -> Bool bridging
        // succeeds for exactly 0 and 1, so checking it first swallowed the
        // NUMBERS 0/1 into "false"/"true" (#1150). Every value reaching this
        // method comes from `JSONSerialization` (see `tryParse`), which boxes
        // JSON booleans as __NSCFBoolean and numbers as __NSCFNumber — so the
        // CoreFoundation type id is the only reliable discriminator.
        if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
          result[key] = numberValue.boolValue ? "true" : "false"
        } else {
          result[key] = numberValue.stringValue
        }
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
