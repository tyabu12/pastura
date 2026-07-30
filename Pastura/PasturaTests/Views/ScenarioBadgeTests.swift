import Testing

@testable import Pastura

/// Pure-logic tests for the ``ScenarioBadge`` → ``ScenarioBadgeStyle`` mapping
/// (ADR-009: assert logic, never rendered output).
///
/// The `captionSegments` tests that used to live here went with
/// `ScenarioSummaryRowFormat`, retired in #1296 — its only production caller was
/// the shared summary row, so the helper and its tests were left asserting code
/// nothing rendered. Browse's equivalent footer logic is covered by
/// ``GalleryCatalogMetricsTests``.
///
/// No `@MainActor`: both enums are `nonisolated` at the type level, so their
/// auto-synthesized `Equatable` conformance is reachable from a nonisolated
/// context (`.claude/rules/swift-isolation.md` Patterns 2 / 5).
@Suite(.timeLimit(.minutes(1)))
struct ScenarioBadgeTests {

  // MARK: - badge style mapping

  @Test func installedBadgeIsSecondaryStyle() {
    #expect(ScenarioBadge.installed.style == .secondary)
  }

  @Test func updateBadgeIsTintStyle() {
    #expect(ScenarioBadge.update.style == .tint)
  }

  @Test func updateRequiredBadgeIsTintStyle() {
    #expect(ScenarioBadge.updateRequired.style == .tint)
  }

  @Test func newBadgeIsTintStyle() {
    #expect(ScenarioBadge.new.style == .tint)
  }

  @Test func badgeLabelsAreNonEmpty() {
    #expect(!ScenarioBadge.installed.label.isEmpty)
    #expect(!ScenarioBadge.update.label.isEmpty)
    #expect(!ScenarioBadge.updateRequired.label.isEmpty)
    #expect(!ScenarioBadge.new.label.isEmpty)
  }
}
