import Testing

@testable import Pastura

/// Unit tests for the Home scenario row's pure display logic
/// (ADR-016 D3). Asserts logic properties only, never rendered output
/// (ADR-009 / `.claude/rules/view-testing.md`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HomeScenarioRowFormatTests {

  // MARK: - Sheep count clamping

  @Test func sheepCountMatchesAgentCountBelowMax() {
    #expect(HomeScenarioRowFormat.rowSheepCount(agentCount: 1) == 1)
    #expect(HomeScenarioRowFormat.rowSheepCount(agentCount: 3) == 3)
    #expect(
      HomeScenarioRowFormat.rowSheepCount(agentCount: HomeScenarioRowFormat.maxRowSheep)
        == HomeScenarioRowFormat.maxRowSheep)
  }

  @Test func sheepCountClampsAboveMax() {
    #expect(
      HomeScenarioRowFormat.rowSheepCount(agentCount: HomeScenarioRowFormat.maxRowSheep + 1)
        == HomeScenarioRowFormat.maxRowSheep)
    #expect(
      HomeScenarioRowFormat.rowSheepCount(agentCount: 100) == HomeScenarioRowFormat.maxRowSheep)
  }

  @Test func sheepCountZeroWhenUnknownOrEmpty() {
    #expect(HomeScenarioRowFormat.rowSheepCount(agentCount: nil) == 0)
    #expect(HomeScenarioRowFormat.rowSheepCount(agentCount: 0) == 0)
  }

  // MARK: - Rounds label

  @Test func roundsLabelNilWhenUnknownOrZero() {
    #expect(HomeScenarioRowFormat.roundsLabel(rounds: nil) == nil)
    #expect(HomeScenarioRowFormat.roundsLabel(rounds: 0) == nil)
  }

  @Test func roundsLabelInterpolatesCount() {
    // Partial match — the localized template varies by locale, but the
    // numeral must appear regardless.
    #expect(HomeScenarioRowFormat.roundsLabel(rounds: 5)?.contains("5") == true)
  }

  // MARK: - Meta-line visibility

  @Test func metaLineHiddenOnlyWhenBothUnknown() {
    #expect(HomeScenarioRowFormat.showsMetaLine(agentCount: nil, rounds: nil) == false)
    #expect(HomeScenarioRowFormat.showsMetaLine(agentCount: 2, rounds: nil) == true)
    #expect(HomeScenarioRowFormat.showsMetaLine(agentCount: nil, rounds: 5) == true)
    #expect(HomeScenarioRowFormat.showsMetaLine(agentCount: 3, rounds: 10) == true)
  }

  // MARK: - Description line limit

  @Test func descriptionLineLimitTwoLinesAtNormalSizes() {
    #expect(HomeScenarioRowFormat.descriptionLineLimit(isAccessibilitySize: false) == 2)
  }

  @Test func descriptionLineLimitUnlimitedAtAccessibilitySizes() {
    #expect(HomeScenarioRowFormat.descriptionLineLimit(isAccessibilitySize: true) == nil)
  }

  // MARK: - Paused-card progress label

  @Test func pausedProgressNilWhenTotalUnknown() {
    #expect(HomeScenarioRowFormat.pausedProgressLabel(currentRound: 3, totalRounds: nil) == nil)
    #expect(HomeScenarioRowFormat.pausedProgressLabel(currentRound: 3, totalRounds: 0) == nil)
  }

  @Test func pausedProgressInterpolatesBothNumbers() {
    let label = HomeScenarioRowFormat.pausedProgressLabel(currentRound: 3, totalRounds: 5)
    #expect(label?.contains("3") == true)
    #expect(label?.contains("5") == true)
  }

  // MARK: - categoryCaption (#748)

  @Test func categoryCaptionNilForLocalScenario() {
    // No category column (local / self-made / preset) ⇒ no leading caption,
    // so the row shows the inference count alone with no dangling separator.
    #expect(HomeScenarioRowFormat.categoryCaption(for: nil) == nil)
  }

  @Test func categoryCaptionNilForUnknownRawValue() {
    // A persisted raw value no longer mapping to a case degrades to nil.
    #expect(HomeScenarioRowFormat.categoryCaption(for: "no_such_category") == nil)
  }

  @Test func categoryCaptionResolvesKnownCategory() {
    #expect(
      HomeScenarioRowFormat.categoryCaption(for: GalleryCategory.gameTheory.rawValue)
        == GalleryCategory.gameTheory.displayName)
  }
}
