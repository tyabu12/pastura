import Foundation

/// A parsed deep-link URL for the Pastura app.
///
/// Supported URL shape: `pastura://scenario/<id>`
/// where `id` matches `^[a-z0-9_]+$` and is 1–128 characters.
nonisolated public enum DeepLinkURL: Equatable, Sendable {
  case scenario(id: String)

  /// Allowed characters in a scenario id.
  private static let allowedIdCharacters: Set<Character> = {
    let lower = "abcdefghijklmnopqrstuvwxyz"
    let digits = "0123456789"
    return Set((lower + digits + "_").map { $0 })
  }()

  /// Parse a URL. Returns nil if the URL does not conform to the
  /// `pastura://scenario/<id>` shape described in the Acceptance criteria:
  /// - scheme must be `pastura` (case-insensitive)
  /// - host must be `scenario` (lowercase exact)
  /// - path must be a single segment `/<id>` with no extra segments
  /// - id must match `^[a-z0-9_]+$` and be 1–128 characters
  /// - no query or fragment allowed
  public static func parse(_ url: URL) -> DeepLinkURL? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }

    // Scheme: case-insensitive "pastura"
    guard components.scheme?.lowercased() == "pastura" else { return nil }

    // Host: case-sensitive "scenario"
    guard components.host == "scenario" else { return nil }

    // No query or fragment
    guard components.query == nil, components.fragment == nil else { return nil }

    // Path must be a single segment: "/<id>"
    // URLComponents.path includes the leading slash.
    let path = components.path
    let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false)
    // After splitting "/<id>" we get ["", "<id>"]. Extra segments or empty id are rejected.
    guard pathComponents.count == 2 else { return nil }
    let id = String(pathComponents[1])

    // Validate id
    guard isValidID(id) else { return nil }

    return .scenario(id: id)
  }

  private static func isValidID(_ id: String) -> Bool {
    guard !id.isEmpty, id.count <= 128 else { return false }
    return id.allSatisfy { allowedIdCharacters.contains($0) }
  }
}
