import Foundation
import Testing

@testable import Pastura

/// Change-detector for ``ShareDestinationLayout`` (#1096). The horizontal
/// destination row is a visual-only surface with no manual test trigger
/// (ADR-009 view-testing rule 4), so its load-bearing layout constants are
/// pinned here rather than rendered. A failure is NOT a bug — it means a
/// code-review-gated layout token drifted (typically in an unrelated
/// refactor); confirm the change passed review, then update the expected
/// value below.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ShareDestinationLayoutTests {

  @Test("Destination-row layout tokens hold their reviewed values")
  func layoutTokens() {
    #expect(ShareDestinationLayout.iconDiameter == 56)
    #expect(ShareDestinationLayout.iconGlyphSize == 24)
    #expect(ShareDestinationLayout.tabWidth == 76)
    #expect(ShareDestinationLayout.previewSide == 176)
  }
}
