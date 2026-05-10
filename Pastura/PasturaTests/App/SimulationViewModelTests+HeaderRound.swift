import Foundation
import Testing

@testable import Pastura

// `headerRound` GameHeader-integration tests for `SimulationViewModel`
// (#313). Sibling-file extension of `SimulationViewModelTests` per
// `.claude/rules/testing.md` — splitting to a fresh `@Suite` would race
// against the parent suite on shared state (in-memory DB seed, etc.).
extension SimulationViewModelTests {

  // MARK: - headerRound (GameHeader integration)

  @Test func headerRoundIsNilBeforeRoundStarted() throws {
    // Pre-`.roundStarted`, `totalRounds == 0` (the initial value), so
    // the pair-or-nothing guard suppresses the ROUND fragment. Pinning
    // this prevents a regression where the stored 0/0 leaks into the
    // header.
    let (sut, _) = try makeSUT()
    #expect(sut.headerRound == nil)
  }

  @Test func headerRoundReflectsRoundStartedEvent() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.roundStarted(round: 1, totalRounds: 3), scenario: scenario)

    #expect(sut.headerRound == GameHeaderRound(current: 1, total: 3))
  }

  @Test func headerRoundUpdatesAcrossMultipleRounds() throws {
    let (sut, scenario) = try makeSUT()

    sut.handleEvent(.roundStarted(round: 1, totalRounds: 3), scenario: scenario)
    sut.handleEvent(.roundStarted(round: 2, totalRounds: 3), scenario: scenario)

    #expect(sut.headerRound == GameHeaderRound(current: 2, total: 3))
  }
}
