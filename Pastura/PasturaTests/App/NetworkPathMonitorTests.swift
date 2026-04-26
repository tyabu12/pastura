import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NetworkPathMonitorTests {

  @Test("MockNetworkPathMonitor exposes synchronously-settable isCellular")
  func mockExposesSyncIsCellular() {
    let mock = MockNetworkPathMonitor()
    #expect(mock.isCellular == false)
    mock.isCellular = true
    #expect(mock.isCellular == true)
    mock.isCellular = false
    #expect(mock.isCellular == false)
  }

  @Test("MockNetworkPathMonitor conforms to NetworkPathMonitoring as a sync getter")
  func mockConformsToProtocolWithSyncGetter() {
    let mock: any NetworkPathMonitoring = MockNetworkPathMonitor(isCellular: true)
    // Reading through the protocol must be sync — no `await`, no `Task.yield()`.
    #expect(mock.isCellular == true)
  }

  @Test("Production NetworkPathMonitor defaults to false before first NWPath callback")
  func productionDefaultsToFalse() {
    // Construction must not block on NWPathMonitor's first callback. The
    // monitor starts asynchronously and updates `isCellular` via a main-actor
    // hop; until then the cached value stays at the safe default.
    let monitor = NetworkPathMonitor()
    #expect(monitor.isCellular == false)
  }
}
