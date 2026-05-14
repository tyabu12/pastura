import Foundation
import Testing
import os

@testable import Pastura

/// Unit tests for `DownloadDelegate`'s reattach state machine.
///
/// These tests exercise the per-task enum routing (`.foreground` /
/// `.reattached`) directly through the delegate's public-internal API, without
/// spinning up a real URLSession. Real-URLSession tests of the
/// `URLSessionModelDownloader.attachToInFlight` plumbing live in
/// `URLSessionModelDownloaderTests+BackgroundSession.swift`; ModelManager-side
/// observer tests live in `ModelManagerTests+*` (item 4).
@Suite("DownloadDelegate reattach state machine", .serialized, .timeLimit(.minutes(1)))
struct DownloadDelegateTests {

  // MARK: - Helpers

  /// Constructs a fake `URLSessionDownloadTask` for use as a taskIdentifier
  /// carrier. URLSession denies direct subclassing of its task types; routing
  /// through a throwaway `URLSession.downloadTask(with:)` gives us a real
  /// task instance with a fresh taskIdentifier. The task is never `.resume()`d
  /// — no network activity is initiated.
  func makeFakeDownloadTask() -> URLSessionDownloadTask {
    let session = URLSession(configuration: .ephemeral)
    let url = URL(string: "https://example.com/probe.gguf")!
    return session.downloadTask(with: url)
  }

  // MARK: - registerReattachedIfAbsent

  @Test("registerReattachedIfAbsent succeeds on a free slot")
  func registerReattachedIfAbsentSucceedsOnFreeSlot() {
    let delegate = DownloadDelegate()
    let (_, continuation) = AsyncStream<DownloadEvent>.makeStream()
    let registered = delegate.registerReattachedIfAbsent(
      taskIdentifier: 42, streamContinuation: continuation
    )
    #expect(registered)
    continuation.finish()  // release for teardown
  }

  @Test("registerReattachedIfAbsent skips when slot is already occupied")
  func registerReattachedIfAbsentIdempotent() {
    let delegate = DownloadDelegate()
    let (_, contA) = AsyncStream<DownloadEvent>.makeStream()
    let (_, contB) = AsyncStream<DownloadEvent>.makeStream()

    let firstRegistration = delegate.registerReattachedIfAbsent(
      taskIdentifier: 99, streamContinuation: contA
    )
    let secondRegistration = delegate.registerReattachedIfAbsent(
      taskIdentifier: 99, streamContinuation: contB
    )

    #expect(firstRegistration)
    #expect(secondRegistration == false)
    contA.finish()
    contB.finish()
  }

  // MARK: - didWriteData routing

  @Test("didWriteData on a .reattached entry yields .progress to the stream")
  func didWriteDataRoutesProgressToReattachedStream() async {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()

    _ = delegate.registerReattachedIfAbsent(
      taskIdentifier: task.taskIdentifier, streamContinuation: continuation
    )

    delegate.urlSession(
      URLSession.shared, downloadTask: task,
      didWriteData: 50, totalBytesWritten: 50, totalBytesExpectedToWrite: 100
    )

    var iter = stream.makeAsyncIterator()
    let received = await iter.next()
    guard case .progress(let fraction) = received else {
      Issue.record("expected .progress, got \(String(describing: received))")
      return
    }
    #expect(fraction == 0.5)
    continuation.finish()
  }

  @Test("didWriteData with unknown total yields capped progress (no NaN)")
  func didWriteDataWithUnknownTotalCaps() async {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
    _ = delegate.registerReattachedIfAbsent(
      taskIdentifier: task.taskIdentifier, streamContinuation: continuation
    )

    delegate.urlSession(
      URLSession.shared, downloadTask: task,
      didWriteData: 100, totalBytesWritten: 100,
      totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown
    )

    var iter = stream.makeAsyncIterator()
    let received = await iter.next()
    guard case .progress(let fraction) = received else {
      Issue.record("expected .progress")
      return
    }
    // Spec: unknown total → fraction is finite (no NaN / Inf). Exact policy
    // is "approach 1.0 but never reach it without a known total".
    #expect(fraction.isFinite)
    #expect(fraction >= 0.0)
    continuation.finish()
  }

  // MARK: - didFinishDownloadingTo on .reattached

  @Test("didFinishDownloadingTo on .reattached stages the file and stores URL")
  func didFinishDownloadingToStagesFile() async throws {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let (_, continuation) = AsyncStream<DownloadEvent>.makeStream()
    _ = delegate.registerReattachedIfAbsent(
      taskIdentifier: task.taskIdentifier, streamContinuation: continuation
    )

    let sourceTemp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".source")
    try Data("staged-bytes".utf8).write(to: sourceTemp)
    defer { try? FileManager.default.removeItem(at: sourceTemp) }

    delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: sourceTemp)

    let stagedURL = delegate.stagedFileURL(forTaskIdentifier: task.taskIdentifier)
    #expect(stagedURL != nil)
    if let stagedURL {
      #expect(FileManager.default.fileExists(atPath: stagedURL.path))
      try? FileManager.default.removeItem(at: stagedURL)
    }
    continuation.finish()
  }

  // MARK: - didCompleteWithError on .reattached — success

  @Test("didCompleteWithError(nil) on .reattached yields .completed(stagedURL) then finishes")
  func didCompleteWithErrorYieldsCompleted() async throws {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
    _ = delegate.registerReattachedIfAbsent(
      taskIdentifier: task.taskIdentifier, streamContinuation: continuation
    )

    let sourceTemp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".source")
    try Data("ok".utf8).write(to: sourceTemp)
    defer { try? FileManager.default.removeItem(at: sourceTemp) }

    delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: sourceTemp)
    delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)

    var collected: [DownloadEvent] = []
    for await event in stream {
      collected.append(event)
    }

    #expect(collected.count == 1)
    guard case .completed(let modelURL) = collected.first else {
      Issue.record("expected .completed terminal event")
      return
    }
    #expect(FileManager.default.fileExists(atPath: modelURL.path))
    try? FileManager.default.removeItem(at: modelURL)
  }

  // MARK: - didCompleteWithError on .reattached — failure

  @Test("didCompleteWithError(error) on .reattached yields .failed and cleans staged file")
  func didCompleteWithErrorYieldsFailedAndCleansStaged() async throws {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
    _ = delegate.registerReattachedIfAbsent(
      taskIdentifier: task.taskIdentifier, streamContinuation: continuation
    )

    let sourceTemp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".source")
    try Data("partial".utf8).write(to: sourceTemp)
    defer { try? FileManager.default.removeItem(at: sourceTemp) }

    delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: sourceTemp)
    let stagedURL = delegate.stagedFileURL(forTaskIdentifier: task.taskIdentifier)

    delegate.urlSession(
      URLSession.shared, task: task,
      didCompleteWithError: URLError(.networkConnectionLost)
    )

    var collected: [DownloadEvent] = []
    for await event in stream {
      collected.append(event)
    }
    #expect(collected.count == 1)
    if case .failed(let error) = collected.first {
      #expect((error as? URLError)?.code == .networkConnectionLost)
    } else {
      Issue.record("expected .failed terminal event")
    }
    // Failure path cleans up the staged file.
    if let stagedURL {
      #expect(FileManager.default.fileExists(atPath: stagedURL.path) == false)
    }
  }

  // MARK: - onTermination cleanup (consumer-drop before terminal)

  @Test("dropping the stream before terminal event cleans up staged file")
  func consumerDropTriggersStagedFileCleanup() async throws {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()

    var continuationRef: AsyncStream<DownloadEvent>.Continuation?
    let stream = AsyncStream<DownloadEvent> { cont in
      continuationRef = cont
      cont.onTermination = { @Sendable [weak delegate] _ in
        delegate?.handleReattachedStreamTermination(taskIdentifier: task.taskIdentifier)
      }
    }
    guard let continuation = continuationRef else {
      Issue.record("continuation not captured")
      return
    }
    _ = delegate.registerReattachedIfAbsent(
      taskIdentifier: task.taskIdentifier, streamContinuation: continuation
    )

    let sourceTemp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".source")
    try Data("bytes".utf8).write(to: sourceTemp)
    defer { try? FileManager.default.removeItem(at: sourceTemp) }

    delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: sourceTemp)
    let stagedURL = delegate.stagedFileURL(forTaskIdentifier: task.taskIdentifier)
    #expect(stagedURL != nil)

    // Drop the stream: finish() triggers onTermination after pending events drain.
    continuation.finish()
    _ = stream  // suppress unused warning
    // Yield to allow onTermination's queued cleanup work to run.
    await Task.yield()
    await Task.yield()
    if let stagedURL {
      #expect(FileManager.default.fileExists(atPath: stagedURL.path) == false)
    }
  }

  // MARK: - No-entry branch safety

  @Test("didCompleteWithError on unregistered task does not crash")
  func didCompleteWithErrorOnUnregisteredTaskIsSafe() {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
    // Reaching here is the success criterion (defensive .debug-level log path).
  }

  @Test("didFinishDownloadingTo on unregistered task does not crash")
  func didFinishDownloadingToOnUnregisteredTaskIsSafe() throws {
    let delegate = DownloadDelegate()
    let task = makeFakeDownloadTask()
    let sourceTemp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".source")
    try Data("x".utf8).write(to: sourceTemp)
    defer { try? FileManager.default.removeItem(at: sourceTemp) }
    delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: sourceTemp)
    // Reaching here is the success criterion (move-to-tempCopy happens but is
    // leaked — documented trade-off for the cold-completion race).
  }

  // MARK: - Background completion handler routing (PR2 #3 plumbing)

  @Test("storeBackgroundCompletionHandler + urlSessionDidFinishEvents fires handler on main, once")
  func backgroundCompletionHandlerInvokedOnceOnMain() async throws {
    let delegate = DownloadDelegate()
    let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
    let mainDuringInvocation = OSAllocatedUnfairLock<Bool>(initialState: false)

    delegate.storeBackgroundCompletionHandler { @Sendable in
      counter.withLock { $0 += 1 }
      mainDuringInvocation.withLock { $0 = Thread.isMainThread }
    }

    // Fire delegate callback from a non-main queue to verify the main-queue hop.
    DispatchQueue.global().async {
      delegate.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
    }
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(counter.withLock { $0 } == 1)
    #expect(mainDuringInvocation.withLock { $0 } == true)

    // Second firing without re-storing: handler must NOT run again
    // (clear-on-extract under lock satisfies the "exactly once" invariant).
    delegate.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(counter.withLock { $0 } == 1)
  }

  @Test("urlSessionDidFinishEvents with no stored handler is a no-op (foreground launch path)")
  func backgroundCompletionHandlerNoStoredHandlerNoOp() async throws {
    let delegate = DownloadDelegate()
    // Slot stays nil — call must not crash and must not invoke anything.
    delegate.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
    try await Task.sleep(nanoseconds: 50_000_000)
    // Reaching here is the success criterion.
  }
}
