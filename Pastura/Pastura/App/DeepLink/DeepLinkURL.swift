import Foundation

/// A parsed deep-link URL for the Pastura app.
///
/// Supported URL shapes:
/// - Custom scheme: `pastura://scenario/<id>` (app-generated; strict — no
///   query or fragment).
/// - Universal Link: `https://pastura.app/s/<id>` and the Japanese mirror
///   `https://pastura.app/ja/s/<id>`. An optional trailing slash is tolerated
///   (Astro serves `/s/<id>/`), and any query or fragment is ignored (social
///   platforms append `?utm_source=…` / `#fbclid=…`).
///
/// Both shapes resolve to the same `.scenario(id:)`, where `id` matches
/// `^[a-z0-9_]+$` and is 1–128 characters. The host is the trust boundary:
/// only `pastura.app` is accepted for the https shape.
nonisolated public enum DeepLinkURL: Equatable, Sendable {
  case scenario(id: String)

  /// Allowed characters in a scenario id.
  private static let allowedIdCharacters: Set<Character> = {
    let lower = "abcdefghijklmnopqrstuvwxyz"
    let digits = "0123456789"
    return Set((lower + digits + "_").map { $0 })
  }()

  /// Parse a URL into a `DeepLinkURL`, or `nil` if it matches neither
  /// supported shape (see the type doc). Dispatches on scheme
  /// (case-insensitive): `pastura` → custom scheme, `https` → Universal Link.
  public static func parse(_ url: URL) -> DeepLinkURL? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    switch components.scheme?.lowercased() {
    case "pastura":
      return parseCustomScheme(components)
    case "https":
      return parseUniversalLink(components)
    default:
      return nil
    }
  }

  /// `pastura://scenario/<id>` — the strict, app-generated custom scheme.
  /// Host must be exactly `scenario`, no query/fragment, single path segment.
  private static func parseCustomScheme(_ components: URLComponents) -> DeepLinkURL? {
    // Host: case-sensitive "scenario"
    guard components.host == "scenario" else { return nil }

    // No query or fragment (app-generated links never carry them)
    guard components.query == nil, components.fragment == nil else { return nil }

    // Path must be a single segment: "/<id>".
    // URLComponents.path includes the leading slash, so "/<id>" splits (keeping
    // empty subsequences) to ["", "<id>"]. Extra segments or empty id → reject.
    let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: false)
    guard pathComponents.count == 2 else { return nil }
    let id = String(pathComponents[1])

    guard isValidID(id) else { return nil }
    return .scenario(id: id)
  }

  /// `https://pastura.app/s/<id>` or `.../ja/s/<id>` — the Universal Link
  /// shape reached from other apps / the share landing page. Lenient about
  /// trailing slash, query, and fragment (real inbound links carry these);
  /// strict about host (the trust boundary) and path structure.
  private static func parseUniversalLink(_ components: URLComponents) -> DeepLinkURL? {
    // Host is the trust boundary — only our own domain (case-insensitive).
    guard components.host?.lowercased() == "pastura.app" else { return nil }

    // Query and fragment are intentionally NOT rejected: the canonical share
    // URL carries a trailing slash (Astro `trailingSlash: 'always'`) and
    // social platforms append `?utm_source=…` / `#fbclid=…`. Dropping empty
    // subsequences absorbs both the leading and any trailing slash.
    var segments = components.path
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    // Strip the optional Japanese-mirror prefix: /ja/s/<id> resolves to the
    // same scenario as /s/<id> (the web page differs only in chrome language).
    if segments.first == "ja" {
      segments = Array(segments.dropFirst())
    }

    // Remaining must be exactly ["s", "<id>"].
    guard segments.count == 2, segments[0] == "s" else { return nil }
    let id = segments[1]

    guard isValidID(id) else { return nil }
    return .scenario(id: id)
  }

  private static func isValidID(_ id: String) -> Bool {
    guard !id.isEmpty, id.count <= 128 else { return false }
    return id.allSatisfy { allowedIdCharacters.contains($0) }
  }
}
