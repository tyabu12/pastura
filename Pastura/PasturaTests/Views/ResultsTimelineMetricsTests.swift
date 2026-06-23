import CoreGraphics
import Testing

@testable import Pastura

/// Change-detector tripwire for the Past Results timeline layout tokens
/// (``ResultsTimelineMetrics``; tab-identity redesign PR1, #767).
///
/// These assertions mirror the source-of-truth constants **by design**. The
/// timeline's rendered appearance (rail, nodes, header spacing) is
/// code-review-gated only (ADR-009 decision 3 — frame / layout tuning is out
/// of scope for automated tests; the final values are tuned on-device). A
/// failure here does NOT mean a bug was found: it means a code-review-gated
/// layout token drifted (typically in an unrelated refactor), and the editor
/// must confirm the change passed code review before updating the expected
/// value. See `.claude/rules/view-testing.md` § "Change-detector tripwire".
///
/// The suite is intentionally **not** `@MainActor`: ``ResultsTimelineMetrics``
/// is `nonisolated`, so a nonisolated test reads its constants directly — this
/// suite also documents that isolation contract.
@Suite("ResultsTimelineMetrics", .timeLimit(.minutes(1)))
struct ResultsTimelineMetricsTests {

  @Test func railGeometryUnchanged() {
    #expect(ResultsTimelineMetrics.railWidth == 2)
    #expect(ResultsTimelineMetrics.railLeadingInset == 7)
    #expect(ResultsTimelineMetrics.rowIndent == 22)
  }

  @Test func nodeSizesUnchanged() {
    #expect(ResultsTimelineMetrics.rowNodeSize == 9)
    #expect(ResultsTimelineMetrics.dayNodeSize == 13)
    #expect(ResultsTimelineMetrics.dayNodeBorderWidth == 2.5)
  }

  @Test func rowSpacingAndPaddingUnchanged() {
    #expect(ResultsTimelineMetrics.rowSpacing == 9)
    #expect(ResultsTimelineMetrics.rowVerticalPadding == 11)
    #expect(ResultsTimelineMetrics.rowHorizontalPadding == 13)
  }

  @Test func daySectionSpacingUnchanged() {
    #expect(ResultsTimelineMetrics.daySectionTopSpacing == 18)
    #expect(ResultsTimelineMetrics.dayHeaderGap == 11)
  }

  @Test func editorialHeaderSpacingUnchanged() {
    #expect(ResultsTimelineMetrics.headerTopPadding == 10)
    #expect(ResultsTimelineMetrics.eyebrowTitleSpacing == 3)
    #expect(ResultsTimelineMetrics.titleCountSpacing == 5)
  }
}
