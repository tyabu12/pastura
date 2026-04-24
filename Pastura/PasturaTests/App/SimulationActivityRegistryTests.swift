import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SimulationActivityRegistryTests {

  @Test func startsIdle() {
    let registry = SimulationActivityRegistry()
    #expect(registry.activeCount == 0)
    #expect(!registry.isActive)
  }

  @Test func enterMarksActive() {
    let registry = SimulationActivityRegistry()
    registry.enter()
    #expect(registry.activeCount == 1)
    #expect(registry.isActive)
  }

  @Test func matchedEnterLeaveReturnsToIdle() {
    let registry = SimulationActivityRegistry()
    registry.enter()
    registry.leave()
    #expect(registry.activeCount == 0)
    #expect(!registry.isActive)
  }

  @Test func nestedEnterStaysActiveUntilAllLeave() {
    let registry = SimulationActivityRegistry()
    registry.enter()
    registry.enter()
    #expect(registry.activeCount == 2)
    #expect(registry.isActive)

    registry.leave()
    #expect(registry.activeCount == 1)
    #expect(registry.isActive, "still active after one leave — second enter outstanding")

    registry.leave()
    #expect(registry.activeCount == 0)
    #expect(!registry.isActive)
  }
}
