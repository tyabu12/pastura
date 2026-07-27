import Foundation
import Testing

@testable import Pastura

/// Guards the Settings → Feedback "Rate Pastura" deep link (#1279).
///
/// The Settings row calls `openURL`, which **fails silently** on an
/// unconstructible or unroutable URL — no error, no visible effect. So a
/// malformed constant would ship undetected; these assertions are the only
/// automated signal.
@Suite(.timeLimit(.minutes(1)))
struct AppStoreLinksTests {

  @Test func writeReviewURLIsConstructible() throws {
    let url = try #require(AppStoreLinks.writeReview)
    #expect(url.scheme == "https")
    #expect(url.host() == "apps.apple.com")
  }

  @Test func writeReviewURLCarriesTheItemIDAndWriteReviewAction() throws {
    let url = try #require(AppStoreLinks.writeReview)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

    #expect(components.path == "/app/id\(AppStoreLinks.appStoreItemID)")
    // The action parameter is what pre-presents the review sheet; without it
    // the link merely opens the product page.
    #expect(components.queryItems?.first(where: { $0.name == "action" })?.value == "write-review")
  }

  /// The store item id is duplicated across the web LP's App Store badges, and
  /// a Swift-side edit is invisible to those. This reads the actual `.astro`
  /// sources and asserts each still carries the Swift constant — an assertion
  /// against a literal in this file would only re-state the constant and could
  /// never detect the divergence it claims to guard.
  ///
  /// Repo-relative paths are resolved from `#filePath` (same technique as
  /// `RecordsCountPluralTests` reading the string catalog), since the test
  /// bundle does not carry `web/`.
  @Test func appStoreItemIDMatchesEveryWebStoreBadge() throws {
    let mirrors = [
      "web/src/pages/index.astro",
      "web/src/pages/ja/index.astro",
      "web/src/pages/404.astro",
      "web/src/components/ScenarioLanding.astro"
    ]

    for relativePath in mirrors {
      let url = Self.repoRoot.appending(path: relativePath)
      let source = try String(contentsOf: url, encoding: .utf8)
      #expect(
        source.contains("id\(AppStoreLinks.appStoreItemID)"),
        "\(relativePath) does not link id\(AppStoreLinks.appStoreItemID)")
    }
  }

  /// `…/Pastura/PasturaTests/Utilities/<this file>` → four levels up.
  private static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Utilities
    .deletingLastPathComponent()  // PasturaTests
    .deletingLastPathComponent()  // Pastura
    .deletingLastPathComponent()  // repo root
}
