import Foundation
import Network
import Observation

/// Reachability monitor exposing the current network's cellular flag as a
/// synchronous, MainActor-isolated property. Drives the cellular consent
/// gate in ``ModelManager.startDownload(descriptor:)``.
///
/// Sync-only protocol — production reads happen at gate-time inside
/// `startDownload`, which is `@MainActor` and synchronous. A continuously
/// observing wrapper backs the production type so the latest path is
/// already cached when the gate fires; a directly-settable mock backs
/// tests.
@MainActor
public protocol NetworkPathMonitoring: AnyObject {
  /// `true` when the current path uses the literal `.cellular` interface.
  /// Narrower than `path.isExpensive` (which also flags personal hotspot
  /// and metered Wi-Fi) — `isExpensive` false-positived in real-device
  /// QA on at least one genuine Wi-Fi (probably VPN / iCloud Private
  /// Relay / carrier-managed Wi-Fi).
  var isCellular: Bool { get }

  /// Awaits the first `NWPathMonitor` callback so a synchronous
  /// `isCellular` read reflects the actual network path. Resolves
  /// immediately if a callback has already fired.
  ///
  /// Use at app-launch sites that fire `startDownload` before the user
  /// has a chance to interact (e.g. `RootView.initialize()` auto-resume
  /// of a `.notDownloaded` active descriptor). Without this `await`,
  /// the launch-window race lets cellular relaunch slip past the gate
  /// because `isCellular` is still at its `false` default — observed
  /// in real-device QA.
  func waitForFirstPath() async
}

/// Production reachability monitor. Continuously observes `NWPathMonitor`
/// on a background queue and bridges path changes to a MainActor-isolated
/// `@Observable` property via a one-frame `Task { @MainActor in ... }` hop.
///
/// Default value is `false` until the first path callback arrives — gate
/// callers that fire before the initial NWPathMonitor callback (the
/// extreme race window is sub-millisecond at app launch) treat the user
/// as Wi-Fi. Documented as accepted risk: cellular gate fires at user-
/// initiated `startDownload` calls, by which time the monitor's first
/// callback has long since run.
@Observable
@MainActor
public final class NetworkPathMonitor: NetworkPathMonitoring {

  public private(set) var isCellular: Bool = false

  /// `true` once the first `pathUpdateHandler` callback has bridged to
  /// MainActor. Drives `waitForFirstPath()` — readers that need the
  /// authoritative `isCellular` value (cellular gate at app launch)
  /// await until this flips.
  public private(set) var hasReceivedFirstPath: Bool = false

  private let monitor: NWPathMonitor
  private let queue: DispatchQueue
  /// Continuations parked by `waitForFirstPath()` callers. Drained
  /// (resumed) on the first `pathUpdateHandler` arrival, then never
  /// repopulated — subsequent waiters return immediately via the
  /// `hasReceivedFirstPath` fast-path.
  private var firstPathContinuations: [CheckedContinuation<Void, Never>] = []

  public init() {
    self.monitor = NWPathMonitor()
    self.queue = DispatchQueue(
      label: "com.pastura.NetworkPathMonitor", qos: .userInitiated)
    monitor.pathUpdateHandler = { [weak self] path in
      let cellular = path.usesInterfaceType(.cellular)
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.isCellular = cellular
        if !self.hasReceivedFirstPath {
          self.hasReceivedFirstPath = true
          let pending = self.firstPathContinuations
          self.firstPathContinuations.removeAll()
          for continuation in pending {
            continuation.resume()
          }
        }
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }

  public func waitForFirstPath() async {
    if hasReceivedFirstPath { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      // Re-check inside the closure — the path could have arrived
      // between the guard above and this body running on MainActor.
      if hasReceivedFirstPath {
        continuation.resume()
        return
      }
      firstPathContinuations.append(continuation)
    }
  }
}

/// Test double for `NetworkPathMonitoring`. Tests set `isCellular`
/// synchronously without going through the production type's
/// background-queue → main-actor hop — see `NetworkPathMonitorTests`
/// and the cellular-gate tests in `ModelManagerTests+CellularGate.swift`.
///
/// Defaults to `hasReceivedFirstPath: true` so existing tests that
/// don't care about the launch-window race continue to work without
/// awaiting. Tests that exercise the race explicitly use
/// `hasReceivedFirstPath: false` + `simulateFirstPathArrival()`.
@MainActor
public final class MockNetworkPathMonitor: NetworkPathMonitoring {
  public var isCellular: Bool
  public private(set) var hasReceivedFirstPath: Bool
  private var firstPathContinuations: [CheckedContinuation<Void, Never>] = []

  public init(isCellular: Bool = false, hasReceivedFirstPath: Bool = true) {
    self.isCellular = isCellular
    self.hasReceivedFirstPath = hasReceivedFirstPath
  }

  public func waitForFirstPath() async {
    if hasReceivedFirstPath { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      if hasReceivedFirstPath {
        continuation.resume()
        return
      }
      firstPathContinuations.append(continuation)
    }
  }

  /// Simulates the first `NWPathMonitor` callback arriving on the
  /// production type. Resumes any awaiters parked by
  /// `waitForFirstPath()`. Idempotent — subsequent calls are no-ops.
  public func simulateFirstPathArrival(isCellular: Bool? = nil) {
    if let isCellular { self.isCellular = isCellular }
    guard !hasReceivedFirstPath else { return }
    hasReceivedFirstPath = true
    let pending = firstPathContinuations
    firstPathContinuations.removeAll()
    for continuation in pending {
      continuation.resume()
    }
  }
}
