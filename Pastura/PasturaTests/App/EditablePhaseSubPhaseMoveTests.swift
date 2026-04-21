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
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c])

    sut.moveSubPhase(id: a.id, to: .then, at: 2)

    #expect(sut.thenPhases.map(\.id) == [b.id, c.id, a.id])
  }

  // MARK: - moveSubPhase within-branch backward

  @Test func moveSubPhaseWithinBranchBackward() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c])

    sut.moveSubPhase(id: c.id, to: .then, at: 0)

    #expect(sut.thenPhases.map(\.id) == [c.id, a.id, b.id])
  }

  // MARK: - moveSubPhase same-branch onto self (no-op)

  @Test func moveSubPhaseSameBranchOntoSelf() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c])

    sut.moveSubPhase(id: b.id, to: .then, at: 1)

    #expect(sut.thenPhases.map(\.id) == [a.id, b.id, c.id])
  }

  // MARK: - moveSubPhase cross-branch

  @Test func moveSubPhaseCrossBranch() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    let d = makePhase()
    let e = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c], elsePhases: [d, e])

    sut.moveSubPhase(id: b.id, to: .else, at: 1)

    #expect(sut.thenPhases.map(\.id) == [a.id, c.id])
    #expect(sut.elsePhases.map(\.id) == [d.id, b.id, e.id])
  }

  // MARK: - moveSubPhase cross-branch into empty target

  @Test func moveSubPhaseCrossBranchIntoEmptyTarget() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c], elsePhases: [])

    sut.moveSubPhase(id: a.id, to: .else, at: 0)

    #expect(sut.thenPhases.map(\.id) == [b.id, c.id])
    #expect(sut.elsePhases.map(\.id) == [a.id])
  }

  // MARK: - destination index > count clamps to end

  @Test func moveSubPhaseDestinationIndexClampsToEnd() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c])

    sut.moveSubPhase(id: a.id, to: .then, at: 99)

    #expect(sut.thenPhases.map(\.id) == [b.id, c.id, a.id])
  }

  // MARK: - unknown UUID is a no-op

  @Test func moveSubPhaseUnknownUUIDIsNoOp() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var sut = makeConditional(thenPhases: [a, b, c])

    sut.moveSubPhase(id: UUID(), to: .then, at: 0)

    #expect(sut.thenPhases.map(\.id) == [a.id, b.id, c.id])
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
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var phases = [a, b, c]

    phases.movePhase(id: a.id, to: 2)

    #expect(phases.map(\.id) == [b.id, c.id, a.id])
  }

  // MARK: - Array<EditablePhase>.movePhase within-list backward

  @Test func arrayMovePhaseBackward() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var phases = [a, b, c]

    phases.movePhase(id: c.id, to: 0)

    #expect(phases.map(\.id) == [c.id, a.id, b.id])
  }

  // MARK: - Array<EditablePhase>.movePhase unknown UUID is a no-op

  @Test func arrayMovePhaseUnknownUUIDIsNoOp() {
    let a = makePhase()
    let b = makePhase()
    let c = makePhase()
    var phases = [a, b, c]

    phases.movePhase(id: UUID(), to: 0)

    #expect(phases.map(\.id) == [a.id, b.id, c.id])
  }
}
