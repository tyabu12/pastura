import Testing
import UIKit

@testable import Pastura

/// Pure `activityItems` composition for ``HighlightShareItem`` (issue #1070).
///
/// The rendered `ImageRenderer` output is not tested (ADR-009 — no view
/// rendering); only the deterministic share-payload shaping is: the image is
/// always present, and the optional link is appended only when set (guarding
/// the no-force-unwrap invariant).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HighlightShareItemTests {

  @Test("Link is appended after the image when present")
  func includesLinkWhenPresent() {
    let url = URL(string: "https://pastura.app")
    let item = HighlightShareItem(image: UIImage(), linkURL: url)
    #expect(item.activityItems.count == 2)
    #expect(item.activityItems.first is UIImage)
    #expect(item.activityItems.last as? URL == url)
  }

  @Test("Only the image is shared when the link is nil")
  func imageOnlyWhenLinkNil() {
    let item = HighlightShareItem(image: UIImage(), linkURL: nil)
    #expect(item.activityItems.count == 1)
    #expect(item.activityItems.first is UIImage)
  }
}
