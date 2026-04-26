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
  /// and metered Wi-Fi) — matches the policy chosen in
  /// `DemoReplayHostView+Routing.swift:isCellularNow()` (since removed).
  var isCellular: Bool { get }
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

  private let monitor: NWPathMonitor
  private let queue: DispatchQueue

  public init() {
    self.monitor = NWPathMonitor()
    self.queue = DispatchQueue(
      label: "com.pastura.NetworkPathMonitor", qos: .userInitiated)
    monitor.pathUpdateHandler = { [weak self] path in
      let cellular = path.usesInterfaceType(.cellular)
      Task { @MainActor [weak self] in
        self?.isCellular = cellular
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }
}

/// Test double for `NetworkPathMonitoring`. Tests set `isCellular`
/// synchronously without going through the production type's
/// background-queue → main-actor hop — see `MockNetworkPathMonitorTests`
/// and the cellular-gate tests in `ModelManagerTests+CellularGate.swift`.
@MainActor
public final class MockNetworkPathMonitor: NetworkPathMonitoring {
  public var isCellular: Bool

  public init(isCellular: Bool = false) {
    self.isCellular = isCellular
  }
}
