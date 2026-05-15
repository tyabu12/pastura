import Foundation
import Testing

@testable import Pastura

// Sibling-file extension of `DownloadDelegateTests` per testing.md split
// rule — keeps the parent suite struct under the 250-line `type_body_length`
// cap while the `.foreground`-stranding regression coverage lives next to
// its smaller sibling cases (still under the same `@Suite`, so the
// `.serialized` trait applies).

extension DownloadDelegateTests {

  @Test("handleReattachedStreamTermination does not strand .foreground entries")
  func handleReattachedStreamTerminationDoesNotStrandForeground() async throws {
    // Regression: if `attachToInFlight`'s slot-occupied branch built a
    // stream and called `finish()` on it, the AsyncStream's onTermination
    // fires `handleReattachedStreamTermination` for a taskIdentifier whose
    // slot may belong to a `.foreground` entry. The pre-fix impl
    // unconditionally `removeValue`d, stranding the foreground
    // continuation (caller hangs forever).
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let taskID = task.taskIdentifier

    // Plant a `.foreground` entry by running `register(...)` from a
    // background Task that parks on the continuation. Released at the end
    // via `didCompleteWithError`.
    typealias DLContinuation = CheckedContinuation<DownloadResult, any Error>
    let parkedTask = Task<Void, Never> {
      _ = try? await withCheckedThrowingContinuation { (cont: DLContinuation) in
        delegate.register(
          taskIdentifier: taskID,
          resumeOffset: 0,
          progressHandler: { _, _ in },
          continuation: cont
        )
      }
    }
    // Yield until the parked Task has reached `register`. Probe via
    // `registerReattachedIfAbsent`: returns false once the foreground slot
    // is occupied.
    for _ in 0..<50 {
      try await Task.sleep(nanoseconds: 1_000_000)
      let (_, probe) = AsyncStream<DownloadEvent>.makeStream()
      let took = delegate.registerReattachedIfAbsent(
        taskIdentifier: taskID, streamContinuation: probe)
      probe.finish()
      if !took { break }
      // Slot was empty — probe took it. Roll back so the parked Task
      // gets the slot on its next iteration.
      delegate.handleReattachedStreamTermination(taskIdentifier: taskID)
    }

    // Fire the method under test against the .foreground-occupied slot.
    delegate.handleReattachedStreamTermination(taskIdentifier: taskID)

    // If the foreground slot were stranded-removed,
    // `registerReattachedIfAbsent` would return true. The fix keeps the
    // foreground entry intact, so it returns false.
    let (_, probe2) = AsyncStream<DownloadEvent>.makeStream()
    let stillOccupied = !delegate.registerReattachedIfAbsent(
      taskIdentifier: taskID, streamContinuation: probe2)
    probe2.finish()
    #expect(stillOccupied, "foreground entry was stranded by handleReattachedStreamTermination")

    // Teardown: release the parked continuation so the Task exits cleanly
    // and Swift Testing doesn't flag a leaked CheckedContinuation.
    delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: URLError(.cancelled))
    await parkedTask.value
  }

  @Test("handleReattachedStreamTermination is a no-op when no entry exists")
  func handleReattachedStreamTerminationNoEntryIsNoOp() {
    let delegate = DownloadDelegate()
    delegate.handleReattachedStreamTermination(taskIdentifier: 99_999)
    // Reaching here is the success criterion (defensive lookup).
  }
}
