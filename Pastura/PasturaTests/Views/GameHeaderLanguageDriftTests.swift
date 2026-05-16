import SwiftUI
import Testing

@testable import Pastura

/// Coverage for the meta-row language-drift badge (#401 item 2) —
/// pure helper output + a11y label composition. Visual placement
/// (right-cluster, before tok/s) is verified manually via the
/// "Sim — drift badge worst case" preview; structural layout is out
/// of scope per ADR-009.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct GameHeaderLanguageDriftTests {

  // MARK: - formatLanguageDriftBadgeText (visual)

  @Test func badgeTextCollapsesAtZero() {
    #expect(GameHeader.formatLanguageDriftBadgeText(count: 0) == nil)
  }

  @Test func badgeTextRendersMultiplierForPositiveCount() {
    #expect(GameHeader.formatLanguageDriftBadgeText(count: 1) == "×1")
    #expect(GameHeader.formatLanguageDriftBadgeText(count: 3) == "×3")
    #expect(GameHeader.formatLanguageDriftBadgeText(count: 99) == "×99")
  }

  // MARK: - formatLanguageDriftAccessibilityFragment (VoiceOver)

  @Test func driftA11yFragmentCollapsesAtZero() {
    #expect(GameHeader.formatLanguageDriftAccessibilityFragment(count: 0) == nil)
  }

  @Test func driftA11yFragmentIncludesCount() {
    let fragment = GameHeader.formatLanguageDriftAccessibilityFragment(count: 3)
    #expect(fragment != nil)
    #expect(fragment?.contains("3") == true)
  }

  // MARK: - metaAccessibilityLabel — drift fragment placement

  @Test func metaA11yLabelOmitsDriftFragmentWhenZero() {
    let label = GameHeader.metaAccessibilityLabel(
      round: GameHeaderRound(current: 2, total: 5),
      phaseLabel: "negotiation", tokensPerSecond: 16.5,
      languageDriftCount: 0)
    #expect(label == "Round 2 / 5, negotiation, 16.5 tok/s")
  }

  @Test func metaA11yLabelAppendsDriftFragmentAfterTokens() {
    // Order contract: ROUND → phase → tok/s → drift. Stop-3 VoiceOver
    // reads in that order so the drift signal sits at the tail of the
    // meta row, after the technical-stat fragments.
    let label = GameHeader.metaAccessibilityLabel(
      round: GameHeaderRound(current: 2, total: 5),
      phaseLabel: "negotiation", tokensPerSecond: 16.5,
      languageDriftCount: 3)
    // Substring assertions tolerate the localized "drift ×N" wording
    // changing without breaking this test.
    #expect(label.hasPrefix("Round 2 / 5, negotiation, 16.5 tok/s"))
    #expect(label.contains("3"))
  }

  @Test func metaA11yLabelIncludesDriftWhenOnlyFragmentPresent() {
    // Defensive: caller passes drift-only (no round / phase / tok/s).
    // Should still announce the drift count.
    let label = GameHeader.metaAccessibilityLabel(
      round: nil, phaseLabel: nil, tokensPerSecond: nil,
      languageDriftCount: 2)
    #expect(label != "")
    #expect(label.contains("2"))
  }

  // MARK: - hasMetaRow gating

  @Test func hasMetaRowReturnsTrueWhenOnlyDriftCountIsPositive() {
    // Pin the contract that the drift fragment alone is enough to
    // mount the meta row — otherwise count > 0 with no round/phase/
    // tokens would silently swallow the badge.
    let header = GameHeader(
      scenarioName: "X", status: .simulating,
      languageDriftCount: 2)
    #expect(header.hasMetaRow == true)
  }

  @Test func hasMetaRowReturnsFalseWhenDriftCountIsZero() {
    let header = GameHeader(
      scenarioName: "X", status: .simulating,
      languageDriftCount: 0)
    #expect(header.hasMetaRow == false)
  }

  @Test func hasMetaRowReturnsFalseWhenDriftCountIsNil() {
    // Demo-path default: caller omits the param entirely.
    let header = GameHeader(scenarioName: "X", status: .demoing)
    #expect(header.hasMetaRow == false)
    #expect(header.languageDriftCount == nil)
  }

  // MARK: - init round-trip

  @Test func driftCountRoundTripsThroughInit() {
    let header = GameHeader(
      scenarioName: "X", status: .simulating,
      languageDriftCount: 5)
    #expect(header.languageDriftCount == 5)
  }
}
