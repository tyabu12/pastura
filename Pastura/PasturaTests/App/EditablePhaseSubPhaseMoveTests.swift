import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct EditablePhaseSubPhaseMoveTests {
  // MARK: - Helpers

  private func makePhase(type: PhaseType = .speakAll) -> EditablePhase {
    EditablePhase(type: type)
  }

  private func makeConditional(
    thenPhases: [EditablePhase] = [],
    elsePhases: [EditablePhase] = []
  ) -> EditablePhase {
    EditablePhase(type: .conditional, thenPhases: thenPhases, elsePhases: elsePhases)
  }

  // MARK: - moveSubPhase within-branch forward

  @Test func moveSubPhaseWithinBranchForward() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC])

    sut.moveSubPhase(id: phaseA.id, to: .then, at: 2)

    #expect(sut.thenPhases.map(\.id) == [phaseB.id, phaseC.id, phaseA.id])
  }

  // MARK: - moveSubPhase within-branch backward

  @Test func moveSubPhaseWithinBranchBackward() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC])

    sut.moveSubPhase(id: phaseC.id, to: .then, at: 0)

    #expect(sut.thenPhases.map(\.id) == [phaseC.id, phaseA.id, phaseB.id])
  }

  // MARK: - moveSubPhase same-branch onto self (no-op)

  @Test func moveSubPhaseSameBranchOntoSelf() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC])

    sut.moveSubPhase(id: phaseB.id, to: .then, at: 1)

    #expect(sut.thenPhases.map(\.id) == [phaseA.id, phaseB.id, phaseC.id])
  }

  // MARK: - moveSubPhase cross-branch

  @Test func moveSubPhaseCrossBranch() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    let phaseD = makePhase()
    let phaseE = makePhase()
    var sut = makeConditional(
      thenPhases: [phaseA, phaseB, phaseC],
      elsePhases: [phaseD, phaseE]
    )

    sut.moveSubPhase(id: phaseB.id, to: .else, at: 1)

    #expect(sut.thenPhases.map(\.id) == [phaseA.id, phaseC.id])
    #expect(sut.elsePhases.map(\.id) == [phaseD.id, phaseB.id, phaseE.id])
  }

  // MARK: - moveSubPhase cross-branch into empty target

  @Test func moveSubPhaseCrossBranchIntoEmptyTarget() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC], elsePhases: [])

    sut.moveSubPhase(id: phaseA.id, to: .else, at: 0)

    #expect(sut.thenPhases.map(\.id) == [phaseB.id, phaseC.id])
    #expect(sut.elsePhases.map(\.id) == [phaseA.id])
  }

  // MARK: - destination index > count clamps to end

  @Test func moveSubPhaseDestinationIndexClampsToEnd() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC])

    sut.moveSubPhase(id: phaseA.id, to: .then, at: 99)

    #expect(sut.thenPhases.map(\.id) == [phaseB.id, phaseC.id, phaseA.id])
  }

  // MARK: - negative destination index clamps to start

  @Test func moveSubPhaseNegativeDestinationIndexClampsToStart() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC])

    sut.moveSubPhase(id: phaseC.id, to: .then, at: -5)

    #expect(sut.thenPhases.map(\.id) == [phaseC.id, phaseA.id, phaseB.id])
  }

  // MARK: - unknown UUID is a no-op

  @Test func moveSubPhaseUnknownUUIDIsNoOp() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var sut = makeConditional(thenPhases: [phaseA, phaseB, phaseC])

    sut.moveSubPhase(id: UUID(), to: .then, at: 0)

    #expect(sut.thenPhases.map(\.id) == [phaseA.id, phaseB.id, phaseC.id])
  }

  // MARK: - SubPhaseDragPayload round-trip

  @Test func subPhaseDragPayloadRoundTrip() throws {
    let id = UUID()
    let original = SubPhaseDragPayload(id: id, sourceBranch: .then)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SubPhaseDragPayload.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.sourceBranch == original.sourceBranch)
  }

  // MARK: - Array<EditablePhase>.movePhase within-list forward

  @Test func arrayMovePhaseForward() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var phases = [phaseA, phaseB, phaseC]

    phases.movePhase(id: phaseA.id, to: 2)

    #expect(phases.map(\.id) == [phaseB.id, phaseC.id, phaseA.id])
  }

  // MARK: - Array<EditablePhase>.movePhase within-list backward

  @Test func arrayMovePhaseBackward() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var phases = [phaseA, phaseB, phaseC]

    phases.movePhase(id: phaseC.id, to: 0)

    #expect(phases.map(\.id) == [phaseC.id, phaseA.id, phaseB.id])
  }

  // MARK: - Array<EditablePhase>.movePhase unknown UUID is a no-op

  @Test func arrayMovePhaseUnknownUUIDIsNoOp() {
    let phaseA = makePhase()
    let phaseB = makePhase()
    let phaseC = makePhase()
    var phases = [phaseA, phaseB, phaseC]

    phases.movePhase(id: UUID(), to: 0)

    #expect(phases.map(\.id) == [phaseA.id, phaseB.id, phaseC.id])
  }
}
