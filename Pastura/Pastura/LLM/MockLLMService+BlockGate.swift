import Foundation
import os

// Signal-blocked generate gate (UI-test hold), carved out of MockLLMService.swift
// to keep that file under the swiftlint `file_length` cap (#726). The gate is a
// self-contained test-helper cluster: it owns the `BlockGate` mode enum and the
// four park/release methods, reaching back into the host only via the
// module-internal `state` lock and `State.blockGate` field.
//
// swift-isolation Pattern 1 + Pattern 3: a sibling-file extension on a
// `nonisolated` type inherits default-MainActor isolation unless marked
// `nonisolated` at the extension level (Pattern 3), and `awaitBlockReleaseIfArmed`
// builds escaping closures via `withTaskCancellationHandler` / `withCheckedContinuation`
// (Pattern 1). Both are addressed by the `nonisolated extension` below.
nonisolated extension MockLLMService {

  /// State of the ``blockGenerateUntilSignal()`` gate. Stored continuation is
  /// non-nil only while a `generate` call is parked. Mirrors
  /// ``SuspendController``'s `idle`/`suspended`/`resumed` shape (incl. its
  /// proven cancel-before-store race fix); `.disabled` is the mode-off default
  /// so the gate is a pure no-op unless explicitly armed.
  enum BlockGate: Sendable {
    case disabled
    case armed(CheckedContinuation<Void, Never>?)
    case released
  }

  // MARK: - Signal-blocked generate (UI-test hold)

  /// Arm `generate` to park (before its not-loaded / suspend / response checks)
  /// until ``unblockGenerate()`` is called or the calling task is cancelled.
  ///
  /// Holds a run in-flight **independent of wall-clock** — replaces the former
  /// `generateDelay` timed sleep so a slow CI runner can never expire the hold
  /// mid-test (#719). The block lives INSIDE `generate` and is **not** released
  /// by a ``SuspendController`` resume, which is the whole point: it stays
  /// distinct from ``suspendOnControllerAttach()`` (a pre-generate *park* that
  /// the `.viewHide` resume gate would clear, letting the generate run on and
  /// exhaust an empty `responses` queue).
  ///
  /// Scope: gates ``generate(system:user:schema:)`` and therefore wrap-mode
  /// ``generateStream(system:user:schema:)``, but NOT explicit
  /// ``setStreamChunks(_:)`` streaming (that path never calls `generate`). The
  /// armed mode is a *configuration* that survives ``reset()`` (like
  /// `controller` / `suspendOnAttach`); ``unblockGenerate()`` releases it.
  public func blockGenerateUntilSignal() {
    state.withLock { $0.blockGate = .armed(nil) }
  }

  /// Release a `generate` parked by ``blockGenerateUntilSignal()`` and latch the
  /// release so a later park returns immediately.
  ///
  /// Idempotent and safe to call before any `generate` parks (the latch makes
  /// the unblock un-loseable). No-op when the gate is `.disabled`.
  public func unblockGenerate() {
    // Extract the parked continuation under the lock, resume OUTSIDE it (the
    // executor enqueue must not run while holding the lock). Mirrors
    // SuspendController.resume().
    let continuation: CheckedContinuation<Void, Never>? = state.withLock { mutableState in
      switch mutableState.blockGate {
      case .disabled, .released:
        return nil
      case .armed(let stored):
        mutableState.blockGate = .released
        return stored
      }
    }
    continuation?.resume()
  }

  /// Park the calling task on an armed block gate until ``unblockGenerate()`` or
  /// task cancellation; return immediately when the gate is `.disabled` /
  /// `.released`. Verbatim-mirrors ``SuspendController/awaitResume()``'s proven
  /// cancel-before-store race fix (#134) — `<Void, Never>` + post-await `checkCancellation()`.
  func awaitBlockReleaseIfArmed() async throws {
    // Fast path: skip the continuation hop when the mode is off, so a default
    // MockLLMService behaves exactly as before.
    let isArmed = state.withLock { mutableState -> Bool in
      if case .disabled = mutableState.blockGate { return false }
      return true
    }
    guard isArmed else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeNow = state.withLock { mutableState -> Bool in
          switch mutableState.blockGate {
          case .disabled, .released:
            // Already released (latched unblock) — return immediately.
            return true
          case .armed(let existing):
            precondition(
              existing == nil,
              "MockLLMService: multi-awaiter block not supported (1 generate = 1 waiter)"
            )
            mutableState.blockGate = .armed(continuation)
            return false
          }
        }
        if resumeNow {
          continuation.resume()
          return
        }
        // onCancel may have fired BEFORE the continuation was installed — it
        // then saw `.armed(nil)` and no-op'd, leaving the just-stored
        // continuation parked forever. Self-resume to close the race.
        if Task.isCancelled {
          extractParkedBlockContinuation()?.resume()
        }
      }
    } onCancel: {
      extractParkedBlockContinuation()?.resume()
    }
    // Distinguish cancellation from a normal unblock for the caller.
    try Task.checkCancellation()
  }

  /// Atomically extract the parked block continuation (if any), clearing it to
  /// `.armed(nil)` so cancel / unblock paths never resume it twice. Resume the
  /// returned value OUTSIDE any lock. Mirrors `extractStoredContinuation()`.
  private func extractParkedBlockContinuation() -> CheckedContinuation<Void, Never>? {
    state.withLock { mutableState in
      guard case .armed(let stored) = mutableState.blockGate, let cont = stored else {
        return nil
      }
      mutableState.blockGate = .armed(nil)
      return cont
    }
  }
}
