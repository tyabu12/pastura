import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct EditablePhaseSubPhaseMoveTests {
  // MARK: - Helpers

  private func makeConditionalPhase(
    thenPhases: [EditablePhase] = [],
    elsePhases: [EditablePhase] = []
  ) -> EditablePhase {
    EditablePhase(type: .conditional, thenPhases: thenPhases, elsePhases: elsePhases)
  }

  private func makeSpeakPhase() -> EditablePhase {
    EditablePhase(type: .speakAll)
  }

  // MARK: - then → else

  @Test func moveSubPhaseFromThenToElse() {
    let phaseA = makeSpeakPhase()
    let phaseB = makeSpeakPhase()
    let phaseC = makeSpeakPhase()
    let phaseD = makeSpeakPhase()

    var sut = makeConditionalPhase(
      thenPhases: [phaseA, phaseB, phaseC],
      elsePhases: [phaseD]
    )

    sut.moveSubPhase(id: phaseB.id, to: .else)

    #expect(sut.thenPhases.map(\.id) == [phaseA.id, phaseC.id])
    #expect(sut.elsePhases.map(\.id) == [phaseD.id, phaseB.id])
  }

  // MARK: - else → then

  @Test func moveSubPhaseFromElseToThen() {
    let phaseA = makeSpeakPhase()
    let phaseD = makeSpeakPhase()
    let phaseE = makeSpeakPhase()
    let phaseF = makeSpeakPhase()

    var sut = makeConditionalPhase(
      thenPhases: [phaseA],
      elsePhases: [phaseD, phaseE, phaseF]
    )

    sut.moveSubPhase(id: phaseE.id, to: .then)

    #expect(sut.thenPhases.map(\.id) == [phaseA.id, phaseE.id])
    #expect(sut.elsePhases.map(\.id) == [phaseD.id, phaseF.id])
  }

  // MARK: - Same-branch no-op

  @Test func moveSubPhaseToSameBranchIsNoOp() {
    let phaseA = makeSpeakPhase()
    let phaseB = makeSpeakPhase()
    let phaseC = makeSpeakPhase()

    var sut = makeConditionalPhase(
      thenPhases: [phaseA, phaseB, phaseC],
      elsePhases: []
    )

    let beforeThen = sut.thenPhases.map(\.id)
    let beforeElse = sut.elsePhases.map(\.id)

    sut.moveSubPhase(id: phaseB.id, to: .then)

    #expect(sut.thenPhases.map(\.id) == beforeThen)
    #expect(sut.elsePhases.map(\.id) == beforeElse)
  }

  // MARK: - Unknown UUID no-op

  @Test func moveSubPhaseWithUnknownIdIsNoOp() {
    let phaseA = makeSpeakPhase()
    let phaseB = makeSpeakPhase()
    let phaseC = makeSpeakPhase()

    var sut = makeConditionalPhase(
      thenPhases: [phaseA, phaseB, phaseC],
      elsePhases: []
    )

    let beforeThen = sut.thenPhases.map(\.id)
    let beforeElse = sut.elsePhases.map(\.id)

    sut.moveSubPhase(id: UUID(), to: .else)

    #expect(sut.thenPhases.map(\.id) == beforeThen)
    #expect(sut.elsePhases.map(\.id) == beforeElse)
  }

  // MARK: - Count invariants

  @Test func moveSubPhaseUpdatesCountsCorrectly() {
    let phases = (0..<3).map { _ in makeSpeakPhase() }
    let elsePhases = (0..<2).map { _ in makeSpeakPhase() }

    var sut = makeConditionalPhase(
      thenPhases: phases,
      elsePhases: elsePhases
    )

    let initialThenCount = sut.thenPhases.count  // 3
    let initialElseCount = sut.elsePhases.count  // 2

    sut.moveSubPhase(id: phases[0].id, to: .else)

    #expect(sut.thenPhases.count == initialThenCount - 1)
    #expect(sut.elsePhases.count == initialElseCount + 1)
  }

  // MARK: - ID preservation

  @Test func moveSubPhasePreservesId() {
    let phaseA = makeSpeakPhase()
    let phaseB = makeSpeakPhase()

    var sut = makeConditionalPhase(
      thenPhases: [phaseA, phaseB],
      elsePhases: []
    )

    let originalId = phaseB.id

    sut.moveSubPhase(id: phaseB.id, to: .else)

    #expect(sut.elsePhases.last?.id == originalId)
  }

  // MARK: - Deep sub-phase no-op

  @Test func moveDeepSubPhaseIsNoOpAtTopLevel() {
    let deepPhase = makeSpeakPhase()
    let innerConditional = makeConditionalPhase(
      thenPhases: [deepPhase],
      elsePhases: []
    )

    var sut = makeConditionalPhase(
      thenPhases: [innerConditional],
      elsePhases: []
    )

    let beforeThen = sut.thenPhases.map(\.id)
    let beforeElse = sut.elsePhases.map(\.id)

    // Deep phase id should NOT be moveable via top-level moveSubPhase
    sut.moveSubPhase(id: deepPhase.id, to: .else)

    #expect(sut.thenPhases.map(\.id) == beforeThen)
    #expect(sut.elsePhases.map(\.id) == beforeElse)
    // The deep phase must still exist in thenPhases[0].thenPhases
    #expect(sut.thenPhases.first?.thenPhases.first?.id == deepPhase.id)
  }
}
