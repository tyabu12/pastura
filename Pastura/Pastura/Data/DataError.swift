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

  /// A write was refused because the existing record is read-only.
  ///
  /// Used when attempting to overwrite a gallery-sourced scenario
  /// (`sourceType == "gallery"`) with a non-gallery payload. Gallery rows
  /// are writable only via the gallery Try/Update flow.
  case readonly(id: String)
}

/// Provides human-readable descriptions so UI alert handlers can show
/// `error.localizedDescription` without mapping each case manually.
extension DataError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .databaseOpenFailed(let description):
      return String(localized: "Database open failed: \(description)")
    case .migrationFailed(let description):
      return String(localized: "Database migration failed: \(description)")
    case .recordNotFound(let type, let id):
      return String(localized: "Record not found: \(type) id=\(id)")
    case .encodingFailed(let description):
      return String(localized: "Encoding failed: \(description)")
    case .decodingFailed(let description):
      return String(localized: "Decoding failed: \(description)")
    case .readonly(let id):
      return String(localized: "Record is read-only: id=\(id)")
    }
  }
}
