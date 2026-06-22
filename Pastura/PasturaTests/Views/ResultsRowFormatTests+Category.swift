import Foundation
import Testing

@testable import Pastura

// Category-caption tests (#748), split into a sibling extension to keep the
// `ResultsRowFormatTests` struct body within SwiftLint's type_body_length cap.
// Same suite (no new `@Suite`) per `.claude/rules/testing.md` — a new suite
// would race the original on shared state.
extension ResultsRowFormatTests {

  @Test func categoryCaptionNilWhenNoMappableCategory() {
    // Local / pre-v10 runs (nil) and raw values that no longer map to a case
    // both degrade to nil ⇒ the Past Results row draws no category line.
    #expect(ResultsRowFormat.categoryCaption(for: nil) == nil)
    #expect(ResultsRowFormat.categoryCaption(for: "no_such_category") == nil)
  }

  @Test func categoryCaptionResolvesKnownCategory() {
    #expect(
      ResultsRowFormat.categoryCaption(for: GalleryCategory.ethics.rawValue)
        == GalleryCategory.ethics.displayName)
  }
}
