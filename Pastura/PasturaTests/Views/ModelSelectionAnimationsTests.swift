import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ModelSelectionAnimationsTests {

  // MARK: - reduceMotion = true: every phase returns nil

  /// All four animation phases (header, horizon, modelRow(0), modelRow(1))
  /// must return `nil` duration under reduceMotion. Asserting the matrix
  /// rather than spot-checking guards against a future phase being added
  /// without the `guard !reduceMotion` early-return — the regression
  /// shape is "one phase leaks motion."
  @Test func duration_nilForEveryPhase_underReduceMotion() {
    let phases: [ModelSelectionAnimations.Phase] = [
      .header,
      .horizon,
      .modelRow(index: 0),
      .modelRow(index: 1)
    ]
    for phase in phases {
      #expect(
        ModelSelectionAnimations.animationDuration(reduceMotion: true, phase: phase) == nil,
        "Phase \(phase) leaked a non-nil duration under reduceMotion")
    }
  }

  @Test func delay_nilForEveryPhase_underReduceMotion() {
    let phases: [ModelSelectionAnimations.Phase] = [
      .header,
      .horizon,
      .modelRow(index: 0),
      .modelRow(index: 1)
    ]
    for phase in phases {
      #expect(
        ModelSelectionAnimations.animationDelay(reduceMotion: true, phase: phase) == nil,
        "Phase \(phase) leaked a non-nil delay under reduceMotion")
    }
  }

  // MARK: - reduceMotion = false: spec values

  @Test func duration_returnsSpecValues_whenAnimating() {
    #expect(
      ModelSelectionAnimations.animationDuration(reduceMotion: false, phase: .header) == 1.0)
    #expect(
      ModelSelectionAnimations.animationDuration(reduceMotion: false, phase: .horizon) == 1.6)
    #expect(
      ModelSelectionAnimations.animationDuration(
        reduceMotion: false, phase: .modelRow(index: 0)) == 1.0)
    #expect(
      ModelSelectionAnimations.animationDuration(
        reduceMotion: false, phase: .modelRow(index: 1)) == 1.0)
  }

  @Test func delay_returnsSpecValues_whenAnimating() {
    #expect(
      ModelSelectionAnimations.animationDelay(reduceMotion: false, phase: .header) == 0.15)
    #expect(
      ModelSelectionAnimations.animationDelay(reduceMotion: false, phase: .horizon) == 0.3)
  }

  /// `modelRow(index:)` delay must increase monotonically with index so
  /// successive sheep "wake" one-after-another, not simultaneously.
  /// If a regression changes the formula to a constant, this test fails.
  @Test func delay_modelRow_isMonotonicByIndex() {
    let delay0 = ModelSelectionAnimations.animationDelay(
      reduceMotion: false, phase: .modelRow(index: 0))
    let delay1 = ModelSelectionAnimations.animationDelay(
      reduceMotion: false, phase: .modelRow(index: 1))
    let delay2 = ModelSelectionAnimations.animationDelay(
      reduceMotion: false, phase: .modelRow(index: 2))

    #expect(delay0 != nil && delay1 != nil && delay2 != nil)
    if let delay0, let delay1, let delay2 {
      #expect(delay0 < delay1)
      #expect(delay1 < delay2)
    }
  }

  /// Specific spec-value: 0.55 + 0.18 × index. Index 0 → 0.55, 1 → 0.73.
  /// Pin the formula so a future "more conservative" tweak surfaces
  /// here rather than landing in a silent visual regression.
  @Test func delay_modelRow_matchesStaggerFormula() {
    #expect(
      ModelSelectionAnimations.animationDelay(
        reduceMotion: false, phase: .modelRow(index: 0)) == 0.55)
    #expect(
      ModelSelectionAnimations.animationDelay(
        reduceMotion: false, phase: .modelRow(index: 1)) == 0.73)
  }
}
