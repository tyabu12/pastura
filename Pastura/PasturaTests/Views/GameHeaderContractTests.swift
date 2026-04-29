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
    // without crashing. The view will render only row 1.
    let header = GameHeader(
      scenarioName: "X", status: .completed,
      currentRound: nil, totalRounds: nil,
      phaseLabel: nil, tokensPerSecond: nil
    )
    #expect(header.scenarioName == "X")
    #expect(header.currentRound == nil)
    #expect(header.totalRounds == nil)
    #expect(header.phaseLabel == nil)
    #expect(header.tokensPerSecond == nil)
  }

  // MARK: - Partial ROUND inputs (one of currentRound/totalRounds nil)

  @Test func acceptsCurrentRoundWithoutTotalRounds() {
    // Documented behavior: `formatRoundLabel` is only called when both
    // are non-nil. Passing one without the other doesn't crash; the
    // ROUND fragment is suppressed. Pinned at the input level here;
    // visual suppression is verified manually.
    let header = GameHeader(
      scenarioName: "X", status: .simulating,
      currentRound: 2, totalRounds: nil
    )
    #expect(header.currentRound == 2)
    #expect(header.totalRounds == nil)
  }
}
