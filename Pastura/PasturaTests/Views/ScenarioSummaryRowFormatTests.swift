import Testing

@testable import Pastura

/// Pure-logic tests for ``ScenarioSummaryRowFormat`` caption assembly and the
/// ``ScenarioBadge`` → ``ScenarioBadgeStyle`` mapping (ADR-009: assert logic,
/// never rendered output).
@Suite(.timeLimit(.minutes(1)))
struct ScenarioSummaryRowFormatTests {
  // MARK: - captionSegments

  @Test func captionJoinsBothHalvesWithDot() {
    let segments = ScenarioSummaryRowFormat.captionSegments(
      leading: "Game Theory", trailing: "~6 inferences")
    #expect(segments == ["Game Theory", "·", "~6 inferences"])
  }

  @Test func captionLeadingOnlyHasNoDot() {
    let segments = ScenarioSummaryRowFormat.captionSegments(
      leading: "Game Theory", trailing: nil)
    #expect(segments == ["Game Theory"])
  }

  @Test func captionTrailingOnlyHasNoDanglingDot() {
    // Home's case: no category (leading nil), only the inference estimate.
    let segments = ScenarioSummaryRowFormat.captionSegments(
      leading: nil, trailing: "~6 inferences")
    #expect(segments == ["~6 inferences"])
  }

  @Test func captionEmptyWhenBothNil() {
    let segments = ScenarioSummaryRowFormat.captionSegments(leading: nil, trailing: nil)
    #expect(segments.isEmpty)
  }

  // MARK: - badge style mapping

  @Test func presetBadgeIsSecondaryStyle() {
    #expect(ScenarioBadge.preset.style == .secondary)
  }

  @Test func installedBadgeIsSecondaryStyle() {
    #expect(ScenarioBadge.installed.style == .secondary)
  }

  @Test func updateBadgeIsTintStyle() {
    #expect(ScenarioBadge.update.style == .tint)
  }

  @Test func badgeLabelsAreNonEmpty() {
    #expect(!ScenarioBadge.preset.label.isEmpty)
    #expect(!ScenarioBadge.installed.label.isEmpty)
    #expect(!ScenarioBadge.update.label.isEmpty)
  }
}
