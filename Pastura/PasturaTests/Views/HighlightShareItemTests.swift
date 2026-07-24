import Testing
import UIKit

@testable import Pastura

/// Pure `activityItems` composition for ``HighlightShareItem`` (issues #1070,
/// #1082, #1263).
///
/// The rendered `ImageRenderer` output is not tested (ADR-009 — no view
/// rendering); only the deterministic share-payload shaping is: the image and
/// caption are always present, no caption variant duplicates the link (#1082),
/// and the optional link is appended only when set (guarding the
/// no-force-unwrap invariant).
///
/// The caption element is a ``ShareCaptionItemSource`` rather than a plain
/// `String` so X can receive the brand hashtag while other destinations do not
/// (#1263). Its branching logic is covered by ``ShareCaptionItemSourceTests``;
/// what matters here is that the substitution preserved the payload contract.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HighlightShareItemTests {

  @Test("Order is image → caption → link, and no caption variant repeats the URL")
  func includesLinkWhenPresent() throws {
    let url = URL(string: "https://pastura.app")
    let item = HighlightShareItem(image: UIImage(), linkURL: url)
    #expect(item.activityItems.count == 3)
    #expect(item.activityItems.first is UIImage)
    #expect(item.activityItems.last as? URL == url)
    // The caption sits between the image and the URL. Assert its type/position
    // (locale-independent) and that NEITHER destination variant folds the link
    // in — #1082 requires the URL to stay a separate activity item, never
    // duplicated in the text, and the X branch must not reintroduce it.
    let source = try #require(item.activityItems[1] as? ShareCaptionItemSource)
    #expect(source.caption(for: nil).contains("pastura.app") == false)
    #expect(ShareCaptionItemSource.xActivityTypes.isEmpty == false)
    for rawValue in ShareCaptionItemSource.xActivityTypes {
      #expect(
        source.caption(for: UIActivity.ActivityType(rawValue)).contains("pastura.app") == false)
    }
  }

  @Test("Image and caption are shared when the link is nil")
  func imageAndCaptionWhenLinkNil() {
    let item = HighlightShareItem(image: UIImage(), linkURL: nil)
    #expect(item.activityItems.count == 2)
    #expect(item.activityItems.first is UIImage)
    #expect(item.activityItems.last is ShareCaptionItemSource)
  }

  @Test("The caption source carries the model-independent highlight caption")
  func captionSourceCarriesTheSharedCaption() throws {
    let item = HighlightShareItem(image: UIImage(), linkURL: nil)
    let source = try #require(item.activityItems.last as? ShareCaptionItemSource)
    #expect(source.baseCaption == HighlightShareItem.caption)
  }
}
