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
}
