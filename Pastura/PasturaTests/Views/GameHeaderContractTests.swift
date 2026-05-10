import SwiftUI
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GameHeaderContractTests {

  // MARK: - Title resolution (ADR-008 first-frame fallback chain)

  @Test func displayedTitleUsesScenarioNameWhenAvailable() {
    let resolved = GameHeader.resolveDisplayedTitle(
      scenarioName: "Word Wolf", initialName: "WW Hint")
    #expect(resolved == "Word Wolf")
  }

  @Test func displayedTitleFallsBackToInitialNameWhenScenarioNameNil() {
    let resolved = GameHeader.resolveDisplayedTitle(
      scenarioName: nil, initialName: "WW Hint")
    #expect(resolved == "WW Hint")
  }

  @Test func displayedTitleFallsBackToEmptyWhenBothNil() {
    let resolved = GameHeader.resolveDisplayedTitle(
      scenarioName: nil, initialName: nil)
    #expect(resolved == "")
  }

  @Test func emptyScenarioNameStillBeatsInitialName() {
    // Pin the contract: `scenarioName: ""` is treated as "the VM
    // resolved to empty" — which the caller should ideally not
    // produce, but if it does, it wins over `initialName`. This
    // protects callers from accidentally re-introducing the
    // first-frame pop-in fixed by ADR-008.
    let resolved = GameHeader.resolveDisplayedTitle(
      scenarioName: "", initialName: "WW Hint")
    #expect(resolved == "")
  }

  // MARK: - ROUND label formatting

  @Test func roundLabelMatchesEnSourceFormat() {
    // "Round 1 / 3" — `.textCase(.uppercase)` on `Typography.metaRound`
    // upper-cases at draw time, so the source string stays mixed-case.
    let label = GameHeader.formatRoundLabel(current: 1, total: 3)
    #expect(label == "Round 1 / 3")
  }

  @Test func roundLabelHandlesMultiDigitRounds() {
    let label = GameHeader.formatRoundLabel(current: 12, total: 100)
    #expect(label == "Round 12 / 100")
  }

  // MARK: - Tok/s formatting

  @Test func tokensPerSecondFormatsToOneDecimal() {
    // 16.5 — exactly representable as a half (16 + 0.5), so the
    // %.1f rounding is platform-stable. See memory:
    // feedback_float_formatter_test_inputs.md (1.85 rounds
    // platform-dependently to 1.8 or 1.9).
    let formatted = GameHeader.formatTokensPerSecond(16.5)
    #expect(formatted == "16.5 tok/s")
  }

  @Test func tokensPerSecondFormatsZero() {
    let formatted = GameHeader.formatTokensPerSecond(0.0)
    #expect(formatted == "0.0 tok/s")
  }

  @Test func tokensPerSecondFormatsLargeValues() {
    let formatted = GameHeader.formatTokensPerSecond(125.0)
    #expect(formatted == "125.0 tok/s")
  }

  // MARK: - Default extendsIntoTopSafeArea (Sim opts out, Demo overrides)

  @Test func defaultDoesNotExtendIntoTopSafeArea() {
    let header = GameHeader(scenarioName: "X", status: .simulating)
    #expect(header.extendsIntoTopSafeArea == false)
  }

  @Test func extendsIntoTopSafeAreaCanBeEnabled() {
    let header = GameHeader(
      scenarioName: "X", status: .demoing, extendsIntoTopSafeArea: true)
    #expect(header.extendsIntoTopSafeArea == true)
  }

  // MARK: - All-nil meta inputs collapse row 2 (sentinel: no fragment renders)

  @Test func acceptsAllNilMetaInputs() {
    // Pin the contract: caller can pass nil for every row-2 slot
    // without crashing. The view will render only row 1. After #313
    // the ROUND fragment is gated on a single `round: GameHeaderRound?`,
    // so the partial-pair test (`currentRound` without `totalRounds`)
    // became unrepresentable and was removed.
    let header = GameHeader(
      scenarioName: "X", status: .completed,
      round: nil, phaseLabel: nil, tokensPerSecond: nil
    )
    #expect(header.scenarioName == "X")
    #expect(header.round == nil)
    #expect(header.phaseLabel == nil)
    #expect(header.tokensPerSecond == nil)
  }

  // MARK: - Round wrapper round-trip (#313)

  @Test func roundWrapperRoundTripsThroughInit() {
    // Pin the contract that `init`'s `round` parameter survives
    // unchanged onto the public `round` property.
    let header = GameHeader(
      scenarioName: "X", status: .simulating,
      round: GameHeaderRound(current: 2, total: 5)
    )
    #expect(header.round == GameHeaderRound(current: 2, total: 5))
  }

  // MARK: - titleAccessibilityLabel composition (#312)

  @Test func titleAccessibilityLabelPutsStatusFirst() {
    // VoiceOver should announce screen state before identity.
    let label = GameHeader.titleAccessibilityLabel(
      scenarioName: "X", initialName: nil, status: .simulating)
    #expect(label.hasPrefix("Simulating"))
  }

  @Test func titleAccessibilityLabelJoinsStatusAndTitleWithSeparator() {
    // The `, ` separator is `String(localized: ", ")` — en resolves to ", ".
    let label = GameHeader.titleAccessibilityLabel(
      scenarioName: "Word Wolf", initialName: nil, status: .simulating)
    #expect(label == "Simulating, Word Wolf")
  }

  @Test func titleAccessibilityLabelFallsBackToInitialName() {
    let label = GameHeader.titleAccessibilityLabel(
      scenarioName: nil, initialName: "WW Hint", status: .demoing)
    #expect(label == "Demoing, WW Hint")
  }

  @Test func titleAccessibilityLabelCollapsesEmptyTitle() {
    // Both nil → title is empty → no trailing separator, status only.
    let label = GameHeader.titleAccessibilityLabel(
      scenarioName: nil, initialName: nil, status: .completed)
    #expect(label == "Completed")
  }

  @Test func titleAccessibilityLabelTreatsEmptyScenarioNameAsTitle() {
    // `scenarioName: ""` wins over `initialName` per `resolveDisplayedTitle`
    // contract (mirrors `emptyScenarioNameStillBeatsInitialName` above).
    // Empty title → collapses to status only.
    let label = GameHeader.titleAccessibilityLabel(
      scenarioName: "", initialName: "WW Hint", status: .simulating)
    #expect(label == "Simulating")
  }

  // MARK: - metaAccessibilityLabel composition (#312)

  @Test func metaAccessibilityLabelReturnsEmptyWhenAllNil() {
    let label = GameHeader.metaAccessibilityLabel(
      round: nil, phaseLabel: nil, tokensPerSecond: nil)
    #expect(label == "")
  }

  @Test func metaAccessibilityLabelIncludesRoundOnly() {
    let label = GameHeader.metaAccessibilityLabel(
      round: GameHeaderRound(current: 2, total: 5),
      phaseLabel: nil, tokensPerSecond: nil)
    #expect(label == "Round 2 / 5")
  }

  @Test func metaAccessibilityLabelIncludesPhaseOnly() {
    let label = GameHeader.metaAccessibilityLabel(
      round: nil, phaseLabel: "negotiation", tokensPerSecond: nil)
    #expect(label == "negotiation")
  }

  @Test func metaAccessibilityLabelIncludesTokensOnly() {
    // 16.5 — exactly representable as a half (16 + 0.5), platform-stable.
    let label = GameHeader.metaAccessibilityLabel(
      round: nil, phaseLabel: nil, tokensPerSecond: 16.5)
    #expect(label == "16.5 tok/s")
  }

  @Test func metaAccessibilityLabelJoinsAllThreeWithSeparator() {
    let label = GameHeader.metaAccessibilityLabel(
      round: GameHeaderRound(current: 2, total: 5),
      phaseLabel: "negotiation", tokensPerSecond: 16.5)
    #expect(label == "Round 2 / 5, negotiation, 16.5 tok/s")
  }
}
