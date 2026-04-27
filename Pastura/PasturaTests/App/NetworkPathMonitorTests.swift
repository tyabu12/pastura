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

  // MARK: - waitForFirstPath

  @Test("waitForFirstPath returns immediately when first path already received")
  func waitForFirstPath_fastPath() async {
    let mock = MockNetworkPathMonitor(isCellular: true, hasReceivedFirstPath: true)
    // Should not park — completes synchronously on the await.
    await mock.waitForFirstPath()
    #expect(mock.hasReceivedFirstPath == true)
  }

  @Test("waitForFirstPath parks until simulateFirstPathArrival fires")
  func waitForFirstPath_slowPath() async {
    let mock = MockNetworkPathMonitor(isCellular: false, hasReceivedFirstPath: false)
    let waitTask = Task { @MainActor in
      await mock.waitForFirstPath()
      return mock.isCellular
    }
    // Yield so the wait task starts and parks on the continuation.
    await Task.yield()
    #expect(mock.hasReceivedFirstPath == false)
    mock.simulateFirstPathArrival(isCellular: true)
    let observed = await waitTask.value
    #expect(observed == true)
    #expect(mock.hasReceivedFirstPath == true)
  }

  @Test("simulateFirstPathArrival resumes multiple parked awaiters")
  func waitForFirstPath_multipleAwaiters() async {
    let mock = MockNetworkPathMonitor(isCellular: false, hasReceivedFirstPath: false)
    let task1 = Task { @MainActor in await mock.waitForFirstPath() }
    let task2 = Task { @MainActor in await mock.waitForFirstPath() }
    await Task.yield()
    mock.simulateFirstPathArrival(isCellular: true)
    _ = await task1.value
    _ = await task2.value
    // Both awaiters resumed without timing out (the @Suite's
    // .timeLimit(.minutes(1)) trait would fail this otherwise).
    #expect(mock.hasReceivedFirstPath == true)
  }

  @Test("simulateFirstPathArrival is idempotent")
  func simulateFirstPathArrival_idempotent() {
    let mock = MockNetworkPathMonitor(isCellular: false, hasReceivedFirstPath: false)
    mock.simulateFirstPathArrival(isCellular: true)
    #expect(mock.isCellular == true)
    mock.simulateFirstPathArrival(isCellular: false)
    // Second call is a no-op for hasReceivedFirstPath; isCellular still
    // updates because that's the regular setter, not gated on first-arrival.
    #expect(mock.hasReceivedFirstPath == true)
    #expect(mock.isCellular == false)
  }
}
