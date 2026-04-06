import Foundation

/// Parsed output from a single LLM inference turn.
///
/// Wraps a `[String: String]` dictionary with typed accessors for common fields.
/// All values are normalized to `String` by `JSONResponseParser` regardless of
/// the original JSON type.
// nonisolated: Models layer must be accessible from any actor (Engine runs off-main).
nonisolated public struct TurnOutput: Codable, Sendable, Equatable {
  /// The raw parsed fields from the LLM's JSON response.
  public let fields: [String: String]

  public init(fields: [String: String]) {
    self.fields = fields
  }

  // MARK: - Typed Accessors

  /// Agent's spoken statement (e.g., speak_all declaration, speak_each comment).
  public var statement: String? { fields["statement"] }

  /// Agent's vote target name.
  public var vote: String? { fields["vote"] }

  /// Agent's chosen action (e.g., "cooperate" or "betray").
  public var action: String? { fields["action"] }

  /// Agent's private inner thought (hidden by default in UI, revealed on tap).
  public var innerThought: String? { fields["inner_thought"] }

  /// Agent's declaration text.
  public var declaration: String? { fields["declaration"] }

  /// Agent's boke (joke) text for comedy scenarios.
  public var boke: String? { fields["boke"] }

  /// Reason for a vote or decision.
  public var reason: String? { fields["reason"] }

  // MARK: - Required Field Access

  /// Returns the value for the given key, or throws if the key is missing or empty.
  ///
  /// - Parameter key: The field key to look up.
  /// - Returns: The non-empty value for the key.
  /// - Throws: ``TurnOutputError/missingField(_:)`` if the key is absent or empty.
  public func require(_ key: String) throws -> String {
    guard let value = fields[key], !value.isEmpty else {
      throw TurnOutputError.missingField(key)
    }
    return value
  }
}

/// Errors related to accessing ``TurnOutput`` fields.
nonisolated public enum TurnOutputError: Error, Sendable, Equatable {
  /// A required field was missing or empty in the LLM response.
  case missingField(String)
}
