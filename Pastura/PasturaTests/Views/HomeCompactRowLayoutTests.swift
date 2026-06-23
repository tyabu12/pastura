import Foundation
import Testing

@testable import Pastura

/// Change-detector tripwire for the editorial ホーム (Home) tab's layout tokens
/// (``HomeHeroLayout`` + ``HomeCompactRowLayout``; tab-identity PR3, 案C 中庸).
///
/// These assertions mirror the source-of-truth constants **by design**. Home's
/// rendered appearance is code-review-gated only (ADR-009 decision 3 — frame /
/// layout bugs are out of automated-test scope, and there is no manual trigger
/// to *see* the editorial hero + compact rows). A failure here does NOT mean a
/// bug was found: it means a code-review-gated visual token drifted, and the
/// editor must confirm the change passed code review before updating the
/// expected value. See `.claude/rules/view-testing.md` § "Change-detector
/// tripwire".
///
/// Suite is `@MainActor` (the canonical change-detector shape, mirroring
/// ``LanguageDriftToastLayoutTests``); MainActor can still read the constants'
/// values, which is all the comparison needs.
@Suite("HomeCompactRowLayout", .timeLimit(.minutes(1)))
@MainActor
struct HomeCompactRowLayoutTests {

  // MARK: - Hero

  @Test func heroCardShapeUnchanged() {
    #expect(HomeHeroLayout.cornerRadius == 18)
    #expect(HomeHeroLayout.horizontalPadding == 17)
    #expect(HomeHeroLayout.verticalPadding == 16)
    #expect(HomeHeroLayout.borderWidth == 1)
  }

  @Test func heroGradientStopsUnchanged() {
    #expect(HomeHeroLayout.gradientStartOpacity == 0.16)
    #expect(HomeHeroLayout.gradientEndOpacity == 0.07)
  }

  @Test func heroContentSpacingUnchanged() {
    #expect(HomeHeroLayout.contentSpacing == 8)
    #expect(HomeHeroLayout.footerTopSpacing == 12)
  }

  @Test func heroEyebrowAndProgressUnchanged() {
    #expect(HomeHeroLayout.eyebrowDotSize == 7)
    #expect(HomeHeroLayout.eyebrowFontSize == 11)
    #expect(HomeHeroLayout.eyebrowTracking == 1.2)
    #expect(HomeHeroLayout.progressFontSize == 12)
  }

  // MARK: - Compact row

  @Test func iconTileShapeUnchanged() {
    #expect(HomeCompactRowLayout.iconTileSize == 34)
    #expect(HomeCompactRowLayout.iconTileCornerRadius == 9)
    #expect(HomeCompactRowLayout.iconTileBackgroundOpacity == 0.10)
    #expect(HomeCompactRowLayout.iconTileBorderWidth == 1)
  }

  @Test func iconGlyphSizesUnchanged() {
    #expect(HomeCompactRowLayout.sheepSize == 20)
    #expect(HomeCompactRowLayout.docGlyphFontSize == 17)
  }

  @Test func rowMetricsUnchanged() {
    #expect(HomeCompactRowLayout.rowSpacing == 11)
    #expect(HomeCompactRowLayout.horizontalPadding == 15)
    #expect(HomeCompactRowLayout.verticalPadding == 11)
  }

  @Test func captionTypographyUnchanged() {
    #expect(HomeCompactRowLayout.captionFontSize == 11)
    #expect(HomeCompactRowLayout.captionTracking == 0.2)
  }
}
