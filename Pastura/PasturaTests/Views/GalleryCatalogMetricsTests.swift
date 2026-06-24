import CoreGraphics
import Testing

@testable import Pastura

/// Change-detector tripwire for the さがす (Browse) catalog-card layout tokens
/// (``GalleryCatalogMetrics``; tab-identity redesign PR2, #777) plus unit
/// coverage of the pure ``GalleryCatalogRowFormat`` helpers.
///
/// The metric assertions mirror the source-of-truth constants **by design**.
/// The card's rendered appearance (art tile, cluster, chip, spacing) is
/// code-review-gated only (ADR-009 decision 3 — frame / layout tuning is out of
/// scope for automated tests; the final values are tuned on-device). A failure
/// here does NOT mean a bug was found: it means a code-review-gated layout token
/// drifted (typically in an unrelated refactor), and the editor must confirm the
/// change passed code review before updating the expected value. See
/// `.claude/rules/view-testing.md` § "Change-detector tripwire".
///
/// The suite is intentionally **not** `@MainActor`: ``GalleryCatalogMetrics``
/// and ``GalleryCatalogRowFormat`` are `nonisolated`, so a nonisolated test
/// reads them directly — this suite also documents that isolation contract.
@Suite("GalleryCatalogMetrics", .timeLimit(.minutes(1)))
struct GalleryCatalogMetricsTests {

  @Test func artTileGeometryUnchanged() {
    #expect(GalleryCatalogMetrics.artTileSize == 74)
    #expect(GalleryCatalogMetrics.artTileCornerRadius == 13)
    #expect(GalleryCatalogMetrics.artSheepSize == 26)
    #expect(GalleryCatalogMetrics.artClusterSpacing == 1)
    #expect(GalleryCatalogMetrics.artTileBorderWidth == 1)
    #expect(GalleryCatalogMetrics.maxClusterSheep == 4)
  }

  @Test func cardChromeUnchanged() {
    #expect(GalleryCatalogMetrics.cardSpacing == 13)
    #expect(GalleryCatalogMetrics.cardCornerRadius == 16)
    #expect(GalleryCatalogMetrics.cardPadding == 13)
  }

  @Test func listRhythmUnchanged() {
    #expect(GalleryCatalogMetrics.listSpacing == 12)
    #expect(GalleryCatalogMetrics.listHorizontalMargin == 16)
  }

  @Test func bodySpacingUnchanged() {
    #expect(GalleryCatalogMetrics.descriptionLineLimit == 2)
    #expect(GalleryCatalogMetrics.titleChipSpacing == 5)
    #expect(GalleryCatalogMetrics.descriptionTopPadding == 6)
    #expect(GalleryCatalogMetrics.footerTopPadding == 7)
  }

  @Test func categoryChipMetricsUnchanged() {
    #expect(GalleryCatalogMetrics.catchipHorizontalPadding == 7)
    #expect(GalleryCatalogMetrics.catchipVerticalPadding == 2)
    #expect(GalleryCatalogMetrics.catchipCornerRadius == 6)
  }

  // MARK: - footerSegments

  @Test func footerSegmentsJoinsBothHalvesWithDot() {
    let segments = GalleryCatalogRowFormat.footerSegments(agentCount: 4, rounds: 6)
    #expect(segments.count == 3)
    #expect(segments[1] == "·")
    // The numeric halves render through the existing %lld keys; assert the
    // count digit appears so a swapped placeholder is caught.
    #expect(segments[0].contains("4"))
    #expect(segments[2].contains("6"))
  }

  @Test func footerSegmentsOmitsMissingHalves() {
    #expect(GalleryCatalogRowFormat.footerSegments(agentCount: 3, rounds: nil).count == 1)
    #expect(GalleryCatalogRowFormat.footerSegments(agentCount: nil, rounds: 5).count == 1)
    // No dangling separator when only one half is present.
    #expect(!GalleryCatalogRowFormat.footerSegments(agentCount: 3, rounds: nil).contains("·"))
  }

  @Test func footerSegmentsEmptyWhenNeitherPresent() {
    #expect(GalleryCatalogRowFormat.footerSegments(agentCount: nil, rounds: nil).isEmpty)
  }

  // MARK: - clusterSheepCount

  @Test func clusterSheepCountClampsToRange() {
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 1) == 1)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 3) == 3)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 4) == 4)
    // Clamped to maxClusterSheep.
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 9) == 4)
  }

  @Test func clusterSheepCountEmptyWhenUnknownOrNonPositive() {
    // Unknown (nil) and non-positive counts draw no sheep — the catalog never
    // fabricates agent data the rest of the app hides.
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: nil) == 0)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 0) == 0)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: -2) == 0)
  }
}
