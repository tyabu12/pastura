import Foundation
import os

/// Coordinates suspend/resume signalling for an in-flight ``LLMService/generate(system:user:)``
/// call.
///
/// The problem this solves: iOS denies Metal GPU work from background within milliseconds
/// of `scenePhase = .background`, faster than the Engine's phase-boundary pause checkpoint
/// can respond. Without a finer-grained interruption mechanism, an in-flight `llama_decode`
/// running on GPU will fail with a Metal error code (e.g. -3) and the simulation breaks.
///
/// Design:
/// - LLM implementations (notably ``LlamaCppService``) poll ``isSuspendRequested()`` at
///   auto-regressive loop iteration boundaries and throw ``LLMError/suspended`` when it
///   returns `true`. Reactive detection of a failed `llama_decode` under active suspend
///   also converts to ``LLMError/suspended``.
/// - The Engine (``LLMCaller``) catches ``LLMError/suspended``, awaits
///   ``awaitResume()``, then retries the same inference. The per-inference retry
///   counter is not consumed by suspend cycles — users can background/foreground freely.
/// - The App layer orchestrates ``requestSuspend()`` and ``resume()`` in response to
///   ``UIApplication`` lifecycle notifications and background-task activation.
///
/// State machine (all transitions protected by `OSAllocatedUnfairLock`):
/// ```
///           requestSuspend()                resume()
///   idle  ───────────────────▶  suspended  ──────────▶  resumed
///    ▲                             │                       │
///    │        requestSuspend()     │                       │
///    └─────────────────────────────┴───────────────────────┘
/// ```
///
/// Contract:
/// - **Single awaiter only.** Concurrent calls to ``awaitResume()`` trap via precondition.
///   The engine uses 1 generate = 1 waiter; anything else is a programming error.
/// - **Idempotent resume.** ``resume()`` is safe to call multiple times, including when
///   no suspend has been requested. This is essential for cleanup paths
///   (cancellation, `defer` blocks) that may race with normal resume.
/// - **Cancellation honored.** If the awaiting task is cancelled, the continuation is
///   resumed and ``awaitResume()`` returns. Callers detect cancellation via
///   `Task.checkCancellation()` or `Task.isCancelled` after the await.
nonisolated public final class SuspendController: @unchecked Sendable {
  // @unchecked Sendable: all mutable state protected by OSAllocatedUnfairLock.

  /// Internal state. Stored continuation is non-nil only while an awaiter is parked.
  private enum State: Sendable {
    case idle
    case suspended(CheckedContinuation<Void, Never>?)
    case resumed
  }

  private let state = OSAllocatedUnfairLock<State>(initialState: .idle)

  /// Creates a controller in the `idle` state.
  public init() {}

  /// Returns `true` if ``requestSuspend()`` has been called and ``resume()``
  /// has not yet been called to clear it.
  ///
  /// Called by generate loops at iteration boundaries.
  public func isSuspendRequested() -> Bool {
    state.withLock { state in
      if case .suspended = state { return true }
      return false
    }
  }

  /// Requests that the generate loop suspend at its next iteration boundary.
  ///
  /// Idempotent: repeated calls without an intervening ``resume()`` are no-ops.
  /// Re-arms after ``resume()`` to begin a new suspend cycle.
  public func requestSuspend() {
    state.withLock { state in
      switch state {
      case .idle, .resumed:
        state = .suspended(nil)
      case .suspended:
        break  // idempotent
      }
    }
  }

  /// Resumes any waiting ``awaitResume()`` caller and transitions to the `resumed` state.
  ///
  /// Idempotent: safe to call multiple times, and safe to call when no suspend was
  /// requested. Required for cleanup paths that may race with a normal resume.
  public func resume() {
    // Extract continuation under lock, resume outside to avoid holding the lock
    // during executor enqueue.
    let continuation: CheckedContinuation<Void, Never>? = state.withLock { state in
      switch state {
      case .idle:
        return nil
      case .suspended(let stored):
        state = .resumed
        return stored
      case .resumed:
        return nil
      }
    }
    continuation?.resume()
  }

  /// Suspends the calling task until ``resume()`` is called, or returns immediately
  /// if the controller is not in a suspended state.
  ///
  /// Cancellation: if the owning `Task` is cancelled while parked, the continuation
  /// is resumed via the cancellation handler and this method returns normally.
  /// Callers should subsequently check `Task.isCancelled` (or call
  /// `Task.checkCancellation()`) to distinguish cancellation from a normal resume.
  ///
  /// - Precondition: At most one awaiter at any time. Concurrent awaiters trap.
  public func awaitResume() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeNow = state.withLock { state -> Bool in
          switch state {
          case .idle, .resumed:
            // Not suspended (or already resumed) — return immediately.
            return true
          case .suspended(let existing):
            precondition(
              existing == nil,
              "SuspendController: multi-awaiter not supported (1 generate = 1 waiter)"
            )
            state = .suspended(continuation)
            return false
          }
        }
        if resumeNow {
          continuation.resume()
        }
      }
    } onCancel: {
      // Extract stored continuation under lock, resume outside.
      // Leave state as `.suspended(nil)` so a subsequent resume() doesn't crash
      // trying to resume a nil or already-resumed continuation.
      let continuation: CheckedContinuation<Void, Never>? = state.withLock { state in
        guard case .suspended(let stored) = state, let cont = stored else { return nil }
        state = .suspended(nil)
        return cont
      }
      continuation?.resume()
    }
  }
}
