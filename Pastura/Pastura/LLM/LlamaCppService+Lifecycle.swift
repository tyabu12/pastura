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
  /// Called by `loadModel`/`unloadModel` to make the model-lifecycle API resilient
  /// to being invoked while inference is still running. This happens in practice
  /// because llama.cpp's C API does not respect Swift `Task` cancellation —
  /// `generate()` always runs to completion even if the owning `Task` is cancelled.
  /// Previously these paths used a `precondition` that crashed the app
  /// (e.g., on `didReceiveMemoryWarning` mid-generate, user cancel mid-generate,
  /// or stream teardown during the auto-regressive loop).
  ///
  /// Cancellation: this wait is intentionally NOT cancellable. Returning early
  /// while generate is still running would cause `unloadModel` to free the C
  /// model/context pointers that generate is actively dereferencing — the
  /// original use-after-free this precondition guarded against. The wait is
  /// bounded by a 30s timeout as a safety net.
  func awaitGenerateIdle(caller: String) async {
    guard isGenerating() else { return }

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
