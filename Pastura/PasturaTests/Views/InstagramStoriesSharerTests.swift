import Testing
import UIKit

@testable import Pastura

/// Pure logic for direct Instagram Stories sharing (#1083): deep-link URL
/// shape, pasteboard sticker payload, App-ID normalization, and availability
/// gating. The UIKit side effects (`UIPasteboard.setItems`,
/// `UIApplication.open` / `canOpenURL`) are not tested (ADR-009 — no UIKit
/// integration); only the deterministic payload/gating shaping is.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InstagramStoriesSharerTests {

  @Test("shareURL carries the App ID as source_application on the stories scheme")
  func shareURLShape() {
    let url = InstagramStoriesSharer.shareURL(appID: "1234567890")
    #expect(url?.scheme == "instagram-stories")
    #expect(
      url?.absoluteString == "instagram-stories://share?source_application=1234567890")
  }

  @Test("pasteboardItem carries the sticker PNG + both gradient colors under Instagram's keys")
  func pasteboardItemKeys() {
    let png = Data([0x01, 0x02, 0x03])
    let item = InstagramStoriesSharer.pasteboardItem(
      stickerImagePNG: png, topColorHex: "#8A9A6C", bottomColorHex: "#6B7852")
    #expect(item["com.instagram.sharedSticker.stickerImage"] as? Data == png)
    #expect(item["com.instagram.sharedSticker.backgroundTopColor"] as? String == "#8A9A6C")
    #expect(item["com.instagram.sharedSticker.backgroundBottomColor"] as? String == "#6B7852")
    #expect(item.count == 3)
  }

  @Test("isAvailable requires both Instagram installed and a non-empty App ID")
  func availabilityGate() {
    #expect(InstagramStoriesSharer.isAvailable(isInstagramInstalled: true, appID: "123"))
    #expect(!InstagramStoriesSharer.isAvailable(isInstagramInstalled: false, appID: "123"))
    #expect(!InstagramStoriesSharer.isAvailable(isInstagramInstalled: true, appID: nil))
    #expect(!InstagramStoriesSharer.isAvailable(isInstagramInstalled: true, appID: ""))
    #expect(!InstagramStoriesSharer.isAvailable(isInstagramInstalled: true, appID: "   "))
  }

  @Test("normalizedAppID collapses nil / empty / whitespace to nil, trims real IDs")
  func normalizeAppID() {
    #expect(StoryShareConfig.normalizedAppID(nil) == nil)
    #expect(StoryShareConfig.normalizedAppID("") == nil)
    #expect(StoryShareConfig.normalizedAppID("   ") == nil)
    #expect(StoryShareConfig.normalizedAppID("1234567890") == "1234567890")
    #expect(StoryShareConfig.normalizedAppID("  123  ") == "123")
  }
}
