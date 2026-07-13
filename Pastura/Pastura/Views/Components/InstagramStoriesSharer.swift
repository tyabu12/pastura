import UIKit

/// Direct share to Instagram Stories via the `instagram-stories://` URL scheme
/// and the `UIPasteboard` sticker contract (#1083).
///
/// Instagram composites a 1:1 `stickerImage` onto a 9:16 gradient background
/// built from `backgroundTopColor` / `backgroundBottomColor`, so the app hands
/// over the existing square highlight card verbatim and never renders a 9:16
/// image itself. A Facebook App ID (a public client identifier —
/// `Info.plist` `FacebookAppID`, read via ``StoryShareConfig``) has been
/// required by Instagram since Jan 2023 and is passed as the
/// `source_application` query parameter. Reference: Meta "Sharing to Stories"
/// (developers.facebook.com/docs/instagram-platform/sharing-to-stories).
@MainActor
enum InstagramStoriesSharer {

  /// URL scheme for the Instagram Stories deep link (also the
  /// `LSApplicationQueriesSchemes` entry the `canOpenURL` probe relies on).
  static let scheme = "instagram-stories"

  /// Raw pasteboard keys defined by Instagram's sharing contract. They are read
  /// by the Instagram app (not a Swift API), so they must be string literals.
  enum PasteboardKey {
    static let stickerImage = "com.instagram.sharedSticker.stickerImage"
    static let backgroundTopColor = "com.instagram.sharedSticker.backgroundTopColor"
    static let backgroundBottomColor = "com.instagram.sharedSticker.backgroundBottomColor"
  }

  // MARK: - Pure logic (unit-tested)

  /// `instagram-stories://share?source_application=<appID>`, or `nil` if the
  /// components can't form a valid URL (guards the no-force-unwrap invariant).
  static func shareURL(appID: String) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "share"
    components.queryItems = [URLQueryItem(name: "source_application", value: appID)]
    return components.url
  }

  /// The pasteboard item Instagram consumes: the square card PNG as a sticker
  /// plus the moss gradient hex colors that become the 9:16 background.
  static func pasteboardItem(
    stickerImagePNG: Data, topColorHex: String, bottomColorHex: String
  ) -> [String: Any] {
    [
      PasteboardKey.stickerImage: stickerImagePNG,
      PasteboardKey.backgroundTopColor: topColorHex,
      PasteboardKey.backgroundBottomColor: bottomColorHex
    ]
  }

  /// Availability requires **both** Instagram installed and a configured App
  /// ID — the deep link no-ops without a `source_application`, so a missing
  /// App ID must hide the entry point exactly as a missing app does.
  static func isAvailable(isInstagramInstalled: Bool, appID: String?) -> Bool {
    StoryShareConfig.normalizedAppID(appID) != nil && isInstagramInstalled
  }

  // MARK: - UIKit shell (side-effecting; not unit-tested per ADR-009)

  /// Whether Instagram is installed, via a `canOpenURL` probe on the stories
  /// scheme (requires the `LSApplicationQueriesSchemes` allowlist entry).
  static var isInstagramInstalled: Bool {
    guard let url = URL(string: "\(scheme)://share") else { return false }
    return UIApplication.shared.canOpenURL(url)
  }

  /// Convenience gate combining the live install probe with the configured App
  /// ID. The custom share sheet reads this to decide whether to offer the
  /// Instagram Stories destination.
  static var isAvailableNow: Bool {
    isAvailable(
      isInstagramInstalled: isInstagramInstalled, appID: StoryShareConfig.facebookAppID)
  }

  /// Writes the sticker payload to the general pasteboard (5-minute expiry, per
  /// Instagram's contract) and opens Instagram Stories. Returns `false` as a
  /// silent no-op when the URL can't be built or Instagram can't be opened —
  /// callers gate on ``isAvailableNow`` first; this re-checks defensively.
  @discardableResult
  static func share(
    stickerImagePNG: Data, topColorHex: String, bottomColorHex: String, appID: String
  ) -> Bool {
    guard let url = shareURL(appID: appID) else { return false }
    let options: [UIPasteboard.OptionsKey: Any] = [
      // 5-minute window matches Instagram's documented expectation; the
      // pasteboard payload is transient hand-off state, not a lasting copy.
      .expirationDate: Date().addingTimeInterval(60 * 5)
    ]
    UIPasteboard.general.setItems(
      [
        pasteboardItem(
          stickerImagePNG: stickerImagePNG,
          topColorHex: topColorHex, bottomColorHex: bottomColorHex)
      ],
      options: options)
    guard UIApplication.shared.canOpenURL(url) else { return false }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
  }
}

/// Reads the operator-configured Facebook App ID (`Info.plist` `FacebookAppID`)
/// that Instagram Stories sharing requires. Kept separate from
/// ``InstagramStoriesSharer`` so the emptiness normalization stays
/// unit-testable without touching `Bundle`.
@MainActor
enum StoryShareConfig {

  /// The configured Facebook App ID, or `nil` when the `Info.plist` value is
  /// absent / empty / whitespace (the dark-until-configured state).
  static var facebookAppID: String? {
    normalizedAppID(Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String)
  }

  /// Trims and collapses empty / whitespace to `nil`; returns a real ID
  /// verbatim (trimmed). Pure — the unit-tested seam for the `Bundle` read.
  static func normalizedAppID(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
