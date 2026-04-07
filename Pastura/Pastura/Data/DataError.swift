import Foundation

/// Errors specific to the Data persistence layer.
///
/// Each case stores a `String` description rather than wrapping `Error` directly,
/// ensuring `Sendable` and `Equatable` conformance for safe cross-actor use.
nonisolated public enum DataError: Error, Sendable, Equatable {
  /// The database file could not be opened or created.
  case databaseOpenFailed(description: String)

  /// A schema migration failed to apply.
  case migrationFailed(description: String)

  /// A record with the given type and ID was not found.
  case recordNotFound(type: String, id: String)

  /// A domain model could not be encoded to its DB representation.
  case encodingFailed(description: String)

  /// A DB record could not be decoded into its domain model.
  case decodingFailed(description: String)
}
