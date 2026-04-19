/// Decides whether a frequently-fired progress callback should propagate to the UI.
///
/// Designed for use by `ModelManager` to throttle URLSession download-progress
/// callbacks (which fire hundreds of times per second for a 3 GB file) down to
/// ~10 Hz, preventing MainActor saturation during long downloads.
///
/// **Usage pattern — why `OSAllocatedUnfairLock`:**
/// The caller must wrap `ProgressThrottle` inside an `OSAllocatedUnfairLock` rather
/// than relying on the struct's value-type copy semantics. Two distinct callsites
/// require this protection:
/// - **Production** URLSession download delegate: the delegate callbacks arrive on
///   URLSession's internal serial queue (not MainActor), so a lock guards mutation
///   against any concurrent resume/cancel calls.
/// - **`MockModelDownloader`** in `@MainActor`-isolated tests: the mock drives
///   progress from MainActor, but a future refactor could move it off; the lock
///   makes the invariant explicit and keeps the test callsite identical to production.
///
/// Uses `ContinuousClock.Instant` (monotonic) rather than `Date` because wall-clock
/// time can step backwards under NTP correction — a risk over a multi-minute download.
nonisolated struct ProgressThrottle {
  /// Default minimum interval between accepted emissions: 100 ms ≈ 10 UI updates/sec.
  ///
  /// 10 Hz is visually smooth for a progress bar while keeping MainActor scheduling
  /// overhead negligible compared to the actual download throughput work.
  static let defaultInterval: Duration = .milliseconds(100)

  private let interval: Duration
  private var lastAccepted: ContinuousClock.Instant?

  init(interval: Duration = Self.defaultInterval) {
    self.interval = interval
  }

  /// Returns `true` if the caller should emit a progress update at `now`.
  ///
  /// - The **first call always returns `true`** so the initial byte-arrival update
  ///   reaches the UI immediately.
  /// - Subsequent calls within `interval` of the last accepted timestamp return `false`.
  /// - Subsequent calls ≥ `interval` after the last accepted timestamp return `true`
  ///   and update the stored timestamp. Skipped calls do **not** advance the timestamp
  ///   — the window is measured from the last *accepted* call, not the last call.
  mutating func shouldEmit(now: ContinuousClock.Instant) -> Bool {
    guard let last = lastAccepted else {
      // First call — always accept.
      lastAccepted = now
      return true
    }
    guard now >= last + interval else {
      return false
    }
    lastAccepted = now
    return true
  }
}
