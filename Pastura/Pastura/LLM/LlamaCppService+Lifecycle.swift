import Foundation
import os

// MARK: - Lifecycle helpers

extension LlamaCppService {

  /// Polls `generatingGuard` until no `generate()` call is in flight.
  ///
  /// Called by `loadModel`/`unloadModel` to make the model-lifecycle API resilient
  /// to being invoked while inference is still running. This happens in practice
  /// because llama.cpp's C API does not respect Swift `Task` cancellation —
  /// `generate()` always runs to completion even if the owning `Task` is cancelled.
  /// Previously these paths used a `precondition` that crashed the app
  /// (e.g., on `didReceiveMemoryWarning` mid-generate, user cancel mid-generate,
  /// or stream teardown during the auto-regressive loop).
  ///
  /// The wait is brief in practice: generate returns within the `maxTokens`
  /// budget (a few seconds at typical tok/s rates). If the caller's own `Task`
  /// is cancelled during the wait, `Task.sleep` throws and we stop polling —
  /// the caller can decide whether to proceed with the load/unload anyway.
  func awaitGenerateIdle(caller: String) async {
    if generatingGuard.withLock({ $0 }) {
      logger.warning("\(caller)() called while generate() in flight — awaiting completion")
    }
    while generatingGuard.withLock({ $0 }) {
      do {
        try await Task.sleep(for: .milliseconds(50))
      } catch {
        // Task was cancelled during the wait. Stop polling and let the caller
        // proceed — they may still need to free resources.
        return
      }
    }
  }
}
