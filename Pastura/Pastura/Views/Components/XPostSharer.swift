import UIKit

/// Share to X (Twitter) via the `x.com/intent/tweet` web intent (#1096).
///
/// X exposes no image-attach deep link — the intent URL accepts only
/// `text` / `url` — so the highlight card *image* is shared through the
/// system share sheet, and this sharer covers the lightweight
/// caption-plus-link post. The `/intent/tweet` endpoint is used deliberately
/// over `/intent/post`: on iOS the latter bounces through an in-app browser
/// into an X-app ↔ Safari redirect loop, while `/intent/tweet` opens the
/// native composer directly. Reference: X Web Intents
/// (docs.x.com/x-for-websites/web-intents/overview).
@MainActor
enum XPostSharer {

  /// The X web-intent composer endpoint. `x.com` (post-rebrand) avoids the
  /// extra `twitter.com` → `x.com` redirect hop.
  static let intentBase = "https://x.com/intent/tweet"

  /// RFC 3986 *unreserved* set — every other character in a query **value** is
  /// percent-encoded, so spaces, `&`, `:`, `/`, `+`, and emoji can never be
  /// misread as URL syntax. `URLComponents` leaves several of those raw inside
  /// a value (the known ampersand-passthrough), which would let a caption `&`
  /// split the query, so the values are encoded by hand instead.
  private static let valueAllowed: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-._~")
    return set
  }()

  // MARK: - Pure logic (unit-tested)

  /// Builds `https://x.com/intent/tweet?text=<text>&url=<link>`, percent-
  /// encoding both params against ``valueAllowed``. `url=` is omitted when
  /// `link` is nil (a URL-less share still pre-fills the caption). Returns
  /// `nil` only if encoding or the final `URL` parse fails — guarding the
  /// no-force-unwrap invariant.
  static func intentURL(text: String, link: URL?) -> URL? {
    guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: valueAllowed)
    else { return nil }
    var query = "text=\(encodedText)"
    if let link,
      let encodedLink = link.absoluteString.addingPercentEncoding(
        withAllowedCharacters: valueAllowed) {
      query += "&url=\(encodedLink)"
    }
    return URL(string: "\(intentBase)?\(query)")
  }

  // MARK: - UIKit shell (side-effecting; not unit-tested per ADR-009)

  /// Opens the X composer pre-filled with `text` (plus `link` when set).
  /// Returns `false` as a silent no-op if the URL can't be built or opened —
  /// the https intent falls through to Safari when the X app is absent, so a
  /// `false` here is genuinely rare.
  @discardableResult
  static func share(text: String, link: URL?) -> Bool {
    guard let url = intentURL(text: text, link: link) else { return false }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
  }
}
