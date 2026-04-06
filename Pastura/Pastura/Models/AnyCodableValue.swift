import Foundation

/// A type-safe wrapper for dynamic YAML values in scenario definitions.
///
/// Scenarios can have arbitrary top-level fields (e.g., `topics`, `words`)
/// with varying structures. This enum captures the common shapes found in
/// preset scenarios while remaining `Codable` and `Sendable`.
///
/// Used by `Scenario.extraData` to hold scenario-specific data that
/// phase handlers access at runtime.
nonisolated public enum AnyCodableValue: Codable, Sendable, Equatable {
  /// A single string value.
  case string(String)

  /// An array of strings (e.g., bokete photo descriptions).
  case array([String])

  /// A string-keyed dictionary (e.g., a single word wolf topic set).
  case dictionary([String: String])

  /// An array of string-keyed dictionaries
  /// (e.g., word wolf topic sets: `[{"majority": "りんご", "minority": "みかん"}, ...]`).
  case arrayOfDictionaries([[String: String]])

  // MARK: - Codable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let stringValue = try? container.decode(String.self) {
      self = .string(stringValue)
      return
    }
    if let arrayOfDicts = try? container.decode([[String: String]].self) {
      self = .arrayOfDictionaries(arrayOfDicts)
      return
    }
    if let arrayValue = try? container.decode([String].self) {
      self = .array(arrayValue)
      return
    }
    if let dictValue = try? container.decode([String: String].self) {
      self = .dictionary(dictValue)
      return
    }

    throw DecodingError.typeMismatch(
      AnyCodableValue.self,
      DecodingError.Context(
        codingPath: decoder.codingPath,
        debugDescription: "Expected String, [String], [String: String], or [[String: String]]"
      )
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .dictionary(let value):
      try container.encode(value)
    case .arrayOfDictionaries(let value):
      try container.encode(value)
    }
  }
}
