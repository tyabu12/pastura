import CoreGraphics

/// Load-bearing layout constants for the Past Results **timeline** rendering
/// (tab-identity redesign PR1, #767): the left rail, the per-section day-header
/// node, and the row nodes that hang off the rail.
///
/// Extracted into a named `nonisolated enum` so the values are
/// **change-detector**-testable without rendering the View
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire"; ADR-009).
/// Only `Equatable` constants live here — `CGFloat`. The big-title `SwiftUI.Font`
/// is **not** `Equatable`, so it stays inline in `ResultsView+Timeline` and is
/// code-review-gated, not asserted here.
///
/// `nonisolated` so the change-detector test reads the constants from a
/// `nonisolated` context without a `@MainActor` suite workaround
/// (swift-isolation.md Pattern 5). Values are tuned on-device — a test failure
/// means a code-review-gated layout token drifted, not a bug (see the test's
/// doc-comment).
nonisolated enum ResultsTimelineMetrics {
  /// Width of the vertical rail stroke running down each date section.
  static let railWidth: CGFloat = 2

  /// Leading inset of the rail from the screen margin — the rail sits this far
  /// in so the day-header node centers on it.
  static let railLeadingInset: CGFloat = 7

  /// Horizontal gap from the rail to a row's leading edge (the rail-to-content
  /// indent). Rows hang to the right of the rail by this much.
  static let rowIndent: CGFloat = 22

  /// Diameter of the small node marker on each row (rail punctuation; the row's
  /// result pill carries the precise status — the dot is at-a-glance only).
  static let rowNodeSize: CGFloat = 9

  /// Diameter of the larger node on a day-section header.
  static let dayNodeSize: CGFloat = 13

  /// Ring stroke width of the day-header node (drawn as an outlined dot so the
  /// rail reads as threading through it).
  static let dayNodeBorderWidth: CGFloat = 2.5

  /// Vertical spacing between consecutive rows within one date section.
  static let rowSpacing: CGFloat = 9

  /// Inner vertical padding of a single timeline row card.
  static let rowVerticalPadding: CGFloat = 11

  /// Inner horizontal padding of a single timeline row card.
  static let rowHorizontalPadding: CGFloat = 13

  /// Top spacing above a day-section header (separates one date group from the
  /// previous group's last row).
  static let daySectionTopSpacing: CGFloat = 18

  /// Gap between the day-header node and its title text.
  static let dayHeaderGap: CGFloat = 11

  /// Top padding of the editorial screen header (eyebrow + big title + count).
  static let headerTopPadding: CGFloat = 10

  /// Vertical gap between the eyebrow line and the big title.
  static let eyebrowTitleSpacing: CGFloat = 3

  /// Vertical gap between the big title and the record-count line.
  static let titleCountSpacing: CGFloat = 5
}
