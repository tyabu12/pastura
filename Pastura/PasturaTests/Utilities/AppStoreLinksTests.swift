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

  /// Change-detector on the store item id. It is duplicated in the web LP's
  /// store badges, so a bad edit here would be invisible to those.
  @Test func appStoreItemIDPinned() {
    #expect(AppStoreLinks.appStoreItemID == "6788409688")
  }
}
