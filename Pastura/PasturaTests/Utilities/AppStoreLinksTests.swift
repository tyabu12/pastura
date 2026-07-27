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
  ///
  /// The mirrors are **discovered**, not listed: a hand-list can only catch
  /// divergence in files it already knows about, and the likelier drift is a
  /// *new* LP page shipping a badge with a stale id.
  @Test func everyWebStoreBadgeUsesTheSameAppStoreItemID() throws {
    let webSource = Self.repoRoot.appending(path: "web/src")
    let enumerator = try #require(
      FileManager.default.enumerator(at: webSource, includingPropertiesForKeys: nil))
    // The LP badges carry a slug (`/app/pastura-local-llms-simulator/id…`)
    // while the in-app link does not (`/app/id…`), so the path segment between
    // host and id is optional.
    let pattern = try Regex(#"apps\.apple\.com/[^"'\s]*?id(\d+)"#)
    var badgeCount = 0

    for case let url as URL in enumerator where url.pathExtension == "astro" {
      let source = try String(contentsOf: url, encoding: .utf8)
      for match in source.matches(of: pattern) {
        let found = String(source[try #require(match[1].range)])
        #expect(
          found == AppStoreLinks.appStoreItemID,
          "\(url.lastPathComponent) links id\(found), expected id\(AppStoreLinks.appStoreItemID)")
        badgeCount += 1
      }
    }

    // Guards the scan itself — a broken path or a changed link shape would
    // otherwise leave this test vacuously green. Four badges ship today.
    #expect(badgeCount >= 4, "found only \(badgeCount) store badges — did the scan break?")
  }

  /// `…/Pastura/PasturaTests/Utilities/<this file>` → four levels up.
  private static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Utilities
    .deletingLastPathComponent()  // PasturaTests
    .deletingLastPathComponent()  // Pastura
    .deletingLastPathComponent()  // repo root
}
