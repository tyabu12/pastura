import Testing
import UIKit

@testable import Pastura

/// Pure `activityItems` composition for ``HighlightShareItem`` (issues #1070,
/// #1082).
///
/// The rendered `ImageRenderer` output is not tested (ADR-009 — no view
/// rendering); only the deterministic share-payload shaping is: the image and
/// caption are always present, the caption never duplicates the link (#1082),
/// and the optional link is appended only when set (guarding the
/// no-force-unwrap invariant).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HighlightShareItemTests {

  @Test("Order is image → caption → link, and the caption never repeats the URL")
  func includesLinkWhenPresent() {
    let url = URL(string: "https://pastura.app")
    let item = HighlightShareItem(image: UIImage(), linkURL: url)
    #expect(item.activityItems.count == 3)
    #expect(item.activityItems.first is UIImage)
    #expect(item.activityItems.last as? URL == url)
    // The caption sits between the image and the URL. Assert its type/position
    // (locale-independent) and that it never folds the link in — #1082 requires
    // the URL to stay a separate activity item, never duplicated in the text.
    let caption = item.activityItems[1] as? String
    #expect(caption != nil)
    #expect(caption?.contains("pastura.app") == false)
  }

  @Test("Image and caption are shared when the link is nil")
  func imageAndCaptionWhenLinkNil() {
    let item = HighlightShareItem(image: UIImage(), linkURL: nil)
    #expect(item.activityItems.count == 2)
    #expect(item.activityItems.first is UIImage)
    #expect(item.activityItems.last is String)
  }
}
