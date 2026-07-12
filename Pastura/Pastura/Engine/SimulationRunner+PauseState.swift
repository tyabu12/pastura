import Synchronization

// `nonisolated` on the extension per swift-isolation.md Pattern 3: a sibling-file
// extension on the `nonisolated` `SimulationRunner` otherwise inherits MainActor
// and breaks the main file's nonisolated callers (the pause path is all static /
// nonisolated). Split out of SimulationRunner.swift to keep that file under the
// `file_length` limit.
nonisolated extension SimulationRunner {
  /// Bundles the pause flag and an optional resume continuation in a single lock,
  /// so the setter can atomically detect "unpaused while someone is waiting" and
  /// resume the continuation without a race.
  ///
  /// Sendable: all access is serialized through the enclosing `Mutex`.
  struct PauseState: Sendable {
    var isPaused = false
    var resumeContinuation: CheckedContinuation<Void, Never>?
    /// Set by `resumeOnce()` whenever no continuation is currently stored.
    /// The next store attempt inside `checkPaused` consumes this flag and
    /// short-circuits without suspending — mirrors the existing
    /// `Task.isCancelled` race handling. Covers both the emit-before-store
    /// window and any pre-arm from outside an active pause cycle.
    var pendingResume = false
  }

  /// Reference-typed box so the non-copyable `Mutex` can be shared by
  /// reference through the value-type `ExecutionContext`. `OSAllocatedUnfairLock`
  /// was itself a class and gave this sharing for free; `Mutex` is a `~Copyable`
  /// struct, so the box is now explicit.
  final class PauseGate: Sendable {
    private let mutex = Mutex<PauseState>(PauseState())
    // `sending` on the parameter and result mirror `Mutex.withLock`'s exact
    // signature — `PauseState` carries a non-`Sendable` `CheckedContinuation`,
    // so the closure transfers it in/out under the lock rather than sharing it.
    func withLock<R>(_ body: (inout sending PauseState) -> sending R) -> sending R {
      mutex.withLock(body)
    }
  }
}
