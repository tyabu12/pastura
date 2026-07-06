import Foundation
import Testing

@testable import Pastura

/// Unit coverage for the pure declaration/action contradiction logic (#916).
///
/// The precision-first rules pinned here (full contradiction only, dirty
/// values disqualify) were fixed by the #916 PR1 harness validation; the
/// 1-of-2 partial case never occurred in those runs, so this suite is its
/// only coverage.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ContradictionDetectionLogicTests {

  private let options = ["cooperate", "betray"]

  // MARK: Full contradictions (badge fires)

  @Test func cooperateDeclaredAllBetrayIsContradiction() {
    #expect(
      ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: ["betray", "betray"], options: options))
  }

  @Test func betrayDeclaredAllCooperateIsContradictionReverse() {
    #expect(
      ContradictionDetectionLogic.isContradiction(
        declared: "betray", actions: ["cooperate", "cooperate"], options: options))
  }

  @Test func singleContradictingActionIsContradiction() {
    #expect(
      ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: ["betray"], options: options))
  }

  @Test func normalizationToleratesCaseAndWhitespace() {
    #expect(
      ContradictionDetectionLogic.isContradiction(
        declared: " Cooperate ", actions: ["BETRAY", "betray\n"], options: options))
  }

  // MARK: Partial / consistent (no badge — strategy ambiguity)

  @Test func partialBetrayalIsNotContradiction() {
    // The 1-of-2 case: betrayed one neighbour, cooperated with the other.
    // Opponent-conditioned strategy, not a provable lie — precision first.
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: ["betray", "cooperate"], options: options))
  }

  @Test func consistentActionsAreNotContradiction() {
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: ["cooperate", "cooperate"], options: options))
  }

  // MARK: Non-option / dirty values (ineligible — no badge)

  @Test func unclearDeclarationIsNotContradiction() {
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "unclear", actions: ["betray", "betray"], options: options))
  }

  @Test func nilDeclarationIsNotContradiction() {
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: nil, actions: ["betray", "betray"], options: options))
  }

  @Test func dirtyDeclarationIsNotContradiction() {
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "betray.", actions: ["cooperate", "cooperate"], options: options))
  }

  @Test func dirtyActionDisqualifiesTheRound() {
    // A raw action that is not a clean option match means the round's
    // actions are not trustworthy — ChooseHandler.validateAction would have
    // coerced it to options[0], which could manufacture a phantom lie.
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: ["betray", "betray!"], options: options))
  }

  @Test func emptyActionsAreNotContradiction() {
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: [], options: options))
  }

  @Test func emptyOptionsAreNotContradiction() {
    #expect(
      !ContradictionDetectionLogic.isContradiction(
        declared: "cooperate", actions: ["betray"], options: []))
  }

  // MARK: chooseOptions(in:)

  @Test func chooseOptionsReadsFirstOptionedChoosePhase() {
    let phases = [
      Phase(type: .speakAll),
      Phase(type: .choose, options: ["cooperate", "betray"])
    ]
    #expect(
      ContradictionDetectionLogic.chooseOptions(in: phases) == ["cooperate", "betray"])
  }

  @Test func chooseOptionsSearchesConditionalBranches() {
    let phases = [
      Phase(
        type: .conditional,
        thenPhases: [Phase(type: .choose, options: ["cooperate", "betray"])])
    ]
    #expect(
      ContradictionDetectionLogic.chooseOptions(in: phases) == ["cooperate", "betray"])
  }

  @Test func chooseOptionsIsEmptyWithoutAnOptionedChoose() {
    let phases = [Phase(type: .speakAll), Phase(type: .choose)]
    #expect(ContradictionDetectionLogic.chooseOptions(in: phases).isEmpty)
  }
}
