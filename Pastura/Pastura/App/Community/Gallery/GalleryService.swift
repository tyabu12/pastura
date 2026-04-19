// App/Community/Gallery/ is a bounded-context grouping under App/, not a
// distinct dependency layer. When community features grow enough to warrant
// their own test target or a Models-only dependency rule, promote this
// directory to a top-level `Community/` module. Until then, callers treat it
// as part of App/. Keep these files free of SwiftUI so promotion is mechanical.

import Foundation

/// Service that fetches the remote Share Board index and downloads individual
/// scenario YAMLs listed in that index.
///
/// Implementations MUST:
/// - Only fetch in response to user-initiated requests (not on app launch).
/// - Verify downloaded YAML against its SHA-256 and fail loudly on mismatch.
/// - Cap response sizes to prevent memory exhaustion from an adversarial
///   or malformed response.
/// - Persist a cached copy of the gallery index so `loadCachedIndex` can
///   serve content offline.
///
/// `refreshIndex` returns `nil` when the server responds 304 Not Modified
/// (the cache is current) and a fresh `GalleryIndex` on 200. Network or
/// decoding errors are thrown.
nonisolated public protocol GalleryService: Sendable {
  /// Returns the cached gallery index, if any. Never touches the network.
  /// Throws `GalleryServiceError.corruptedCache` if the cached file exists
  /// but cannot be decoded.
  func loadCachedIndex() throws -> GalleryIndex?

  /// Refreshes the cached gallery index from the network using an
  /// ETag-conditional GET. Returns the new index on 200, or `nil` on 304.
  func refreshIndex() async throws -> GalleryIndex?

  /// Downloads a scenario YAML from `url`, verifying the bytes' SHA-256
  /// matches `expectedSHA256` (lowercase hex). Throws
  /// `GalleryServiceError.hashMismatch` on mismatch.
  func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String
}

/// Errors produced by conforming `GalleryService` implementations.
nonisolated public enum GalleryServiceError: Error, Sendable, Equatable {
  /// The response body exceeded the configured size cap (bytes).
  case responseTooLarge(limit: Int)

  /// The downloaded bytes' SHA-256 does not match the expected hash.
  case hashMismatch(expected: String, actual: String)

  /// The response was not `HTTPURLResponse` or a required field was missing.
  case invalidResponse

  /// The server returned an unexpected HTTP status code.
  case unexpectedStatus(Int)

  /// The cached file exists but could not be decoded (corrupted or schema shift).
  case corruptedCache
}

/// Provides human-readable descriptions so UI alert handlers can show
/// `error.localizedDescription` without mapping each case manually.
extension GalleryServiceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .responseTooLarge(let limit):
      return String(localized: "Gallery response exceeds size limit (\(limit) bytes)")
    case .hashMismatch(let expected, let actual):
      return String(
        localized: "Gallery scenario hash mismatch (expected \(expected), got \(actual))")
    case .invalidResponse:
      return String(localized: "Gallery response was malformed")
    case .unexpectedStatus(let code):
      return String(localized: "Gallery server returned unexpected status \(code)")
    case .corruptedCache:
      return String(localized: "Gallery cache is corrupted")
    }
  }
}
