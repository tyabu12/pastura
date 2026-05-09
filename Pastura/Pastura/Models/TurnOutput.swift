import Foundation

/// Parsed output from a single LLM inference turn.
///
/// Wraps a `[String: String]` dictionary with typed accessors for common fields.
/// All values are normalized to `String` by `JSONResponseParser` regardless of
/// the original JSON type.
nonisolated public struct TurnOutput: Codable, Sendable, Equatable {
  /// The raw parsed fields from the LLM's JSON response.
  public let fields: [String: String]

  /// The unfiltered pre-parse LLM emission. Populated by
  /// ``JSONResponseParser/parse(_:)`` so that
  /// ``TurnRecord/rawOutput`` can store the original model output for
  /// audit (matching its documented contract). Absent (`nil`) for
  /// synthetic `TurnOutput` values constructed directly from `fields`
  /// in tests / replay paths.
  ///
  /// Excluded from `Codable` (see ``CodingKeys``) so the encoded shape
  /// used by ``TurnRecord/parsedOutputJSON`` stays stable and does not
  /// duplicate the ~1–2 KB of raw text already held in
  /// ``TurnRecord/rawOutput``. Ignored by `Equatable` because it is
  /// provenance metadata — two outputs with identical fields but
  /// different raw inputs represent the same domain value.
  public let rawText: String?

  public init(fields: [String: String], rawText: String? = nil) {
    self.fields = fields
    self.rawText = rawText
  }

  private enum CodingKeys: String, CodingKey {
    case fields
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.fields = try container.decode([String: String].self, forKey: .fields)
    self.rawText = nil
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(fields, forKey: .fields)
  }

  public static func == (lhs: TurnOutput, rhs: TurnOutput) -> Bool {
    lhs.fields == rhs.fields
  }

  // MARK: - Typed Accessors

  /// Agent's spoken statement (canonical primary field for speak phases).
  public var statement: String? { fields["statement"] }

  /// Agent's vote target name (canonical primary field for `.vote` phases).
  public var vote: String? { fields["vote"] }

  /// Agent's chosen action (canonical primary field for `.choose` phases —
  /// e.g., "cooperate" or "betray"). `OutputSchema.from(phase:)` binds this
  /// field to a GBNF enum constraint when the phase has non-empty `options`.
  public var action: String? { fields["action"] }

  /// Agent's private inner thought (hidden by default in UI, revealed on tap).
  public var innerThought: String? { fields["inner_thought"] }

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

  /// Phase-aware extraction of the "primary" display text — the string
  /// that represents an agent's main visible action for the phase type.
  /// Used by UI and by streaming divergence telemetry to align a partial
  /// extractor snapshot with the canonical parse result.
  ///
  /// Speak / choose phases return the value at
  /// ``ScenarioConventions/primaryField(for:)`` (canonical-field lookup).
  /// `.vote` returns a composite `→ <voted> (<reason>)` string so the
  /// markdown export and live UI surface the reason inline. Code phases
  /// have no LLM output and return `nil`.
  public func primaryText(for phaseType: PhaseType) -> String? {
    if phaseType == .vote {
      return vote.map { voted in
        let reasonPart = reason.map { " (\($0))" } ?? ""
        return "→ \(voted)\(reasonPart)"
      }
    }
    guard let key = ScenarioConventions.primaryField(for: phaseType) else {
      return nil
    }
    return fields[key]
  }
}

/// Errors related to accessing ``TurnOutput`` fields.
nonisolated public enum TurnOutputError: Error, Sendable, Equatable {
  /// A required field was missing or empty in the LLM response.
  case missingField(String)
}
