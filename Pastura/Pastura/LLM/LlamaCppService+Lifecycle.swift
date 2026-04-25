import Foundation
import os

// MARK: - Lifecycle helpers

extension LlamaCppService {

  /// Maximum time `awaitGenerateIdle` will wait before giving up.
  /// A single generate is bounded by `maxTokens` × per-token latency; 30s covers
  /// even slow CPU inference. If this ever fires, something is wrong elsewhere.
  private static let awaitGenerateTimeoutSeconds: TimeInterval = 30

  /// Waits until no `generate()` call is in flight before returning.
  ///
  /// Called by `loadModel`/`unloadModel` (model-lifecycle resilience) and by
  /// `generate`/`generateStream` themselves at entry (Issue #221 — back-to-back
  /// run paths where the prior call's defer-clear hasn't completed yet). All
  /// four sites use the same primitive because llama.cpp's C API does not
  /// respect Swift `Task` cancellation: `generate()` always runs to completion
  /// even if the owning `Task` is cancelled. Previously the lifecycle paths
  /// used a `precondition` that crashed the app on legitimate cleanup paths
  /// (`didReceiveMemoryWarning` mid-generate, stream teardown during the
  /// auto-regressive loop); the generate-entry path used the same pattern and
  /// crashed the app on in-app back-navigation followed by a new simulation.
  ///
  /// Cancellation: this wait is intentionally NOT cancellable. Returning early
  /// while generate is still running would let `unloadModel` (or a follow-on
  /// `generate`) operate on C model/context pointers that the in-flight
  /// generate is actively dereferencing — the original use-after-free this
  /// precondition guarded against. The wait is bounded by a 30s timeout as
  /// a safety net.
  func awaitGenerateIdle(caller: String) async {
    guard isGenerating() else {
      // Diagnostic log for #84 Bug 3: confirms whether reload raced through
      // during throttle's 200ms sleep (in which case isGenerating() == false
      // even though a generate is logically about to run).
      logger.info("\(caller)() awaitGenerateIdle: idle on entry — proceeding immediately")
      return
    }

    logger.warning("\(caller)() called while generate() in flight — awaiting completion")
    let deadline = Date().addingTimeInterval(Self.awaitGenerateTimeoutSeconds)

    while isGenerating() {
      if Date() > deadline {
        let timeout = Self.awaitGenerateTimeoutSeconds
        logger.error(
          "\(caller)() timed out after \(timeout)s — proceeding despite in-flight generate"
        )
        return
      }
      // Detached task inherits no cancellation, so the sleep completes even if
      // the caller's Task is cancelled. Safety (avoid use-after-free) is more
      // important than cooperative cancellation for cleanup paths.
      await Task.detached {
        try? await Task.sleep(for: .milliseconds(50))
      }.value
    }
  }

  /// Atomic wait-and-claim primitive used by `generate` / `generateStream`.
  ///
  /// Combines `awaitGenerateIdle`'s polling with the guard claim into a
  /// single check-and-set so multiple concurrent waiters cannot all observe
  /// the flag clear and then race past a separate `withLock` claim. Returns
  /// once the caller exclusively owns `generatingGuard` (set to `true`); the
  /// caller is responsible for clearing the flag on exit (via `defer`).
  ///
  /// ## Why a separate primitive from `awaitGenerateIdle`
  ///
  /// `loadModel` / `unloadModel` use `awaitGenerateIdle` because they
  /// only need to know "no generate is in flight" — they don't claim the
  /// guard themselves (their own state machine uses `loadedState`).
  /// `generate` / `generateStream`, in contrast, MUST atomically transition
  /// the flag from clear to claimed: separating the wait and the claim
  /// permits a multi-waiter race where the first claimant traps every
  /// subsequent waiter on a now-true flag (Issue #221 post-initial-fix
  /// regression — log evidence of three concurrent waiters
  /// [`generateStream` retry × 2 + `unloadModel`] converging on a single
  /// flag-clear event).
  ///
  /// ## Cancellation
  ///
  /// NOT cancellable, for the same use-after-free reason as
  /// `awaitGenerateIdle`. Returning early while another generate holds
  /// the flag would let `unloadModel` (or this caller's own load-check)
  /// race C-pointer ownership.
  ///
  /// - Parameter caller: Diagnostic label for the warning log emitted on
  ///   first observed contention. Use `"generate"` / `"generateStream"`.
  func acquireGenerateGuard(caller: String) async {
    let deadline = Date().addingTimeInterval(Self.awaitGenerateTimeoutSeconds)
    var loggedWaiting = false
    while true {
      if tryClaimGeneratingGuard() { return }
      if !loggedWaiting {
        logger.warning(
          "\(caller)() called while generate() in flight — awaiting completion")
        loggedWaiting = true
      }
      if Date() > deadline {
        let timeout = Self.awaitGenerateTimeoutSeconds
        logger.error(
          "\(caller)() timed out after \(timeout)s acquiring guard — force-claiming despite contention"
        )
        // Force-claim: prefer degraded safety (use-after-free risk) over
        // a permanent hang. Matches `awaitGenerateIdle`'s "proceed despite
        // in-flight" timeout behavior; if this ever fires, something else
        // is fundamentally broken (likely a stuck inference or livelock).
        forceClaimGeneratingGuard()
        return
      }
      // Detached task — see awaitGenerateIdle. Same use-after-free reason
      // requires this poll to be cancellation-immune.
      await Task.detached {
        try? await Task.sleep(for: .milliseconds(50))
      }.value
    }
  }
}
