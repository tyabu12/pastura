import Foundation
import Testing
import os

@testable import Pastura

/// Unit tests for ``SuspendController``.
///
/// Serialized because several tests spawn child `Task`s that wait on the
/// controller; concurrent execution of unrelated tests is still fine, but
/// interleaving inside this suite risks flaky timings.
@Suite(.serialized)
struct SuspendControllerTests {

  // MARK: - Initial state

  @Test func isSuspendRequestedInitiallyFalse() {
    let controller = SuspendController()
    #expect(!controller.isSuspendRequested())
  }

  // MARK: - requestSuspend

  @Test func requestSuspendSetsSuspendRequestedTrue() {
    let controller = SuspendController()
    controller.requestSuspend()
    #expect(controller.isSuspendRequested())
  }

  @Test func requestSuspendIsIdempotent() {
    let controller = SuspendController()
    controller.requestSuspend()
    controller.requestSuspend()
    controller.requestSuspend()
    #expect(controller.isSuspendRequested())
  }

  // MARK: - resume

  @Test func resumeClearsSuspendRequested() {
    let controller = SuspendController()
    controller.requestSuspend()
    controller.resume()
    #expect(!controller.isSuspendRequested())
  }

  @Test func resumeWithoutSuspendIsNoOp() {
    let controller = SuspendController()
    // Must not crash and state stays idle.
    controller.resume()
    #expect(!controller.isSuspendRequested())
  }

  @Test func resumeCalledMultipleTimesIsIdempotent() {
    let controller = SuspendController()
    controller.requestSuspend()
    controller.resume()
    controller.resume()
    controller.resume()
    #expect(!controller.isSuspendRequested())
  }

  // MARK: - awaitResume immediate return

  @Test func awaitResumeReturnsImmediatelyWhenIdle() async {
    let controller = SuspendController()
    // No suspend requested — should return without hanging.
    await controller.awaitResume()
  }

  @Test func awaitResumeReturnsImmediatelyWhenAlreadyResumed() async {
    let controller = SuspendController()
    controller.requestSuspend()
    controller.resume()
    // State is .resumed — next awaitResume returns immediately.
    await controller.awaitResume()
  }

  // MARK: - awaitResume blocks until resume

  @Test func awaitResumeBlocksUntilResumeIsCalled() async throws {
    let controller = SuspendController()
    controller.requestSuspend()

    let completedBeforeResume = OSAllocatedUnfairLock<Bool>(initialState: false)

    let awaitTask = Task<Void, Never> {
      await controller.awaitResume()
      completedBeforeResume.withLock { $0 = true }
    }

    // Give the await task a moment to park its continuation. If awaitResume
    // incorrectly returned immediately, the flag would already be true.
    try await Task.sleep(for: .milliseconds(100))
    let didCompleteEarly = completedBeforeResume.withLock { $0 }
    #expect(!didCompleteEarly, "awaitResume must not return before resume() is called")

    controller.resume()
    await awaitTask.value
    let didCompleteAfterResume = completedBeforeResume.withLock { $0 }
    #expect(didCompleteAfterResume)
  }

  // MARK: - Cancellation

  @Test func cancellationReleasesAwaitResume() async throws {
    let controller = SuspendController()
    controller.requestSuspend()

    let awaitTask = Task<Void, Never> {
      await controller.awaitResume()
    }

    // Let the continuation park, then cancel.
    try await Task.sleep(for: .milliseconds(50))
    awaitTask.cancel()

    // Task must complete even though resume() was never called.
    await awaitTask.value
  }

  @Test func resumeAfterCancellationIsSafe() async throws {
    // Regression: onCancel resumes the continuation and clears the stored slot.
    // A subsequent resume() must not try to double-resume the same continuation.
    let controller = SuspendController()
    controller.requestSuspend()

    let awaitTask = Task<Void, Never> {
      await controller.awaitResume()
    }

    try await Task.sleep(for: .milliseconds(50))
    awaitTask.cancel()
    await awaitTask.value

    // Must not crash — this is the double-resume guard.
    controller.resume()
    #expect(!controller.isSuspendRequested())
  }

  @Test func awaitResumeBailsOutWhenTaskIsAlreadyCancelledAtEntry() async {
    // Regression: `withTaskCancellationHandler` fires `onCancel` synchronously
    // when the Task is already cancelled at entry, but the body still runs
    // normally. If onCancel sees the pre-install state (.suspended(nil)) it
    // no-ops — and the subsequently-installed continuation parks forever.
    // The fix is a post-install Task.isCancelled self-check in awaitResume.
    //
    // This test is timing-independent: the yield-loop guarantees the child
    // observes cancellation BEFORE entering awaitResume.
    let controller = SuspendController()
    controller.requestSuspend()

    let awaitTask = Task<Void, Never> {
      // Wait until cancellation is observable before calling awaitResume.
      while !Task.isCancelled {
        await Task.yield()
      }
      await controller.awaitResume()
    }

    awaitTask.cancel()
    await awaitTask.value  // must not hang
  }

  // MARK: - Lifecycle cycling

  @Test func requestSuspendAfterResumeStartsNewCycle() async throws {
    let controller = SuspendController()

    // First cycle
    controller.requestSuspend()
    #expect(controller.isSuspendRequested())
    controller.resume()
    #expect(!controller.isSuspendRequested())

    // Second cycle: fully exercise request + awaitResume + resume
    controller.requestSuspend()
    #expect(controller.isSuspendRequested())

    let awaitTask = Task<Void, Never> {
      await controller.awaitResume()
    }
    try await Task.sleep(for: .milliseconds(50))
    controller.resume()
    await awaitTask.value
    #expect(!controller.isSuspendRequested())
  }
}
