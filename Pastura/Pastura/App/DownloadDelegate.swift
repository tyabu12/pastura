import Foundation
import os

// MARK: - Download Result

/// Value returned from `DownloadDelegate` to `URLSessionModelDownloader`'s
/// per-task continuation. Internal-by-default (was `private` in
/// `ModelDownloader.swift` before the file was split for `file_length` cap;
/// sibling-file access requires module-internal visibility).
struct DownloadResult: Sendable {
  let tempURL: URL
  let statusCode: Int
}

// MARK: - Per-Task State

/// State held in `DownloadDelegate.taskStates` for one in-flight task, keyed
/// by `URLSessionTask.taskIdentifier`.
///
/// - `resumeOffset`: added to URLSession's `totalBytesWritten` so reported
///   progress reflects the absolute byte position when resuming via the
///   explicit `Range:` header path.
/// - `progressHandler`: caller-supplied `@Sendable` closure invoked from the
///   delegate queue.
/// - `continuation`: per-task `CheckedContinuation`, resumed exactly once in
///   `didCompleteWithError`.
/// - `downloadedFileURL`: temp URL where `didFinishDownloadingTo` staged the
///   file (set on success, consumed by `didCompleteWithError`).
struct PerTaskState: Sendable {
  // All fields are Sendable: Int64 / Sendable closure / CheckedContinuation
  // (Sendable since Swift 5.7 when T+E are Sendable — DownloadResult is
  // Sendable, `any Error` is implicitly Sendable via the error-throwing
  // contract) / URL?. The mutable `var downloadedFileURL` is fine for
  // value-type Sendable; the struct is always dict-stored under
  // `OSAllocatedUnfairLock`, so mutation race is structurally precluded.
  let resumeOffset: Int64
  let progressHandler: @Sendable (Int64, Int64) -> Void
  let continuation: CheckedContinuation<DownloadResult, any Error>
  var downloadedFileURL: URL?
}

// MARK: - Download Delegate

/// Session-level multi-task delegate. One instance per `URLSessionModelDownloader`,
/// shared across all concurrent download tasks created on that session.
///
/// ## Why keyed by `taskIdentifier`, not URL
///
/// The same download URL can produce two distinct `URLSessionDownloadTask`
/// instances during retry-overlap or future cross-launch reattach paths (PR2).
/// Keying by `URLSessionTask.taskIdentifier` — process-unique per session —
/// avoids the URL collision.
///
/// ## Threading
///
/// - URLSession invokes the `URLSessionDownloadDelegate` protocol methods on
///   the session's serial delegate queue (off-MainActor; `delegateQueue: nil`
///   creates a private serial `OperationQueue`).
/// - `register(taskIdentifier:...)` is called synchronously from
///   `URLSessionModelDownloader.download(...)` (nonisolated context) before
///   `URLSessionDownloadTask.resume()`, so the per-task state is always in
///   the map before the first `didWriteData` callback fires.
/// - `taskStates` is guarded by `OSAllocatedUnfairLock` to coordinate the two
///   access paths.
///
/// ## Lifecycle
///
/// - Created in `URLSessionModelDownloader.init`; lives for the lifetime of
///   the `URLSessionModelDownloader` instance (the process, for `.shared`).
/// - **`finishTasksAndInvalidate()` is intentionally NOT called** in
///   `didCompleteWithError` — invalidating the singleton session would break
///   every subsequent download. The pre-refactor per-call-session pattern
///   invalidated on every completion; the singleton pattern requires the
///   session to outlive any individual task.
///
/// ## Pattern 4 — class-level `nonisolated` required
///
/// `register(...)` is a synchronous instance method on a `Sendable`-protocol-
/// conforming `@unchecked Sendable` class. Without class-level `nonisolated`,
/// the project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would bind
/// the class to MainActor and break calls from `URLSessionModelDownloader`
/// (itself nonisolated). The diagnostic surfaces at the use site, not the
/// declaration. See `.claude/rules/swift-isolation.md` § Pattern 4.
nonisolated final class DownloadDelegate: NSObject, URLSessionDownloadDelegate,
  @unchecked Sendable {
  // @unchecked Sendable: `taskStates` — the only mutable state — is guarded
  // by `OSAllocatedUnfairLock`.

  /// Per-task state map. Lifecycle:
  /// - Entry added in `register(...)` before `task.resume()`.
  /// - `downloadedFileURL` slot mutated in `didFinishDownloadingTo`.
  /// - Entry atomically removed and consumed in `didCompleteWithError`,
  ///   where the continuation is resumed exactly once.
  private let taskStates: OSAllocatedUnfairLock<[Int: PerTaskState]> = .init(initialState: [:])

  /// `.debug`-level logger for delegate-internal trace. The notice-level
  /// telemetry lives on `URLSessionModelDownloader`.
  private static let logger = Logger(
    subsystem: "com.tyabu12.Pastura", category: "DownloadDelegate")

  /// Registers per-task state for a freshly-created `URLSessionDownloadTask`.
  ///
  /// Must be called BEFORE `URLSessionDownloadTask.resume()` — URLSession
  /// can fire `didWriteData` on its first packet, and an empty map at that
  /// point would silently drop progress reporting until completion.
  func register(
    taskIdentifier: Int,
    resumeOffset: Int64,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void,
    continuation: CheckedContinuation<DownloadResult, any Error>
  ) {
    let state = PerTaskState(
      resumeOffset: resumeOffset,
      progressHandler: progressHandler,
      continuation: continuation,
      downloadedFileURL: nil
    )
    taskStates.withLock { $0[taskIdentifier] = state }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    // Snapshot resumeOffset + handler under the lock; invoke handler outside.
    // Holding the lock across the user callback risks deadlock if the handler
    // (in a future iteration) calls back into a downloader API that also
    // touches taskStates.
    let snapshot = taskStates.withLock { map -> (Int64, (@Sendable (Int64, Int64) -> Void))? in
      guard let state = map[downloadTask.taskIdentifier] else { return nil }
      return (state.resumeOffset, state.progressHandler)
    }
    guard let (resumeOffset, handler) = snapshot else { return }
    let received = resumeOffset + totalBytesWritten
    let total: Int64 =
      totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown
      ? resumeOffset + totalBytesExpectedToWrite : -1
    handler(received, total)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // URLSession deletes the file at `location` after this method returns.
    // Move it to a stable temp path so `didCompleteWithError` can hand it to
    // the continuation safely.
    let tempCopy = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".gguf.tmp")
    let movedURL: URL?
    do {
      try FileManager.default.moveItem(at: location, to: tempCopy)
      movedURL = tempCopy
    } catch {
      Self.logger.error(
        """
        didFinishDownloadingTo: failed to move staged temp — \
        taskID=\(downloadTask.taskIdentifier, privacy: .public) \
        errorCode=\((error as NSError).code, privacy: .public)
        """)
      movedURL = nil
    }
    taskStates.withLock { $0[downloadTask.taskIdentifier]?.downloadedFileURL = movedURL }
  }

  // MARK: - URLSessionTaskDelegate

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    // Atomic remove-and-extract: the entry is gone from the map before the
    // continuation resumes. Prevents a hypothetical future task with the
    // same `taskIdentifier` (process-unique within a session, but could
    // overlap during cross-launch reattach in PR2) from colliding with
    // stale state.
    let state = taskStates.withLock { $0.removeValue(forKey: task.taskIdentifier) }
    guard let state else {
      // Spurious callback for an unregistered task. In PR1 this is genuinely
      // unexpected (we cancel orphans on cold start; no other path produces
      // unregistered tasks), so log at `.error` for visibility.
      //
      // TODO(PR2): When `attachToInFlight` lands, callbacks for tasks created
      // in a prior process generation become routine (the OS delivers them
      // before the reattach map is populated, in the narrow window between
      // session construction and reattach). Drop this log level to `.debug`
      // or remove the branch entirely depending on the reattach design.
      Self.logger.error(
        """
        didCompleteWithError: unregistered taskID=\(task.taskIdentifier, privacy: .public) \
        — ignoring (no PerTaskState in map)
        """)
      return
    }

    if let error {
      state.continuation.resume(throwing: error)
      return
    }

    guard let tempURL = state.downloadedFileURL else {
      state.continuation.resume(throwing: URLError(.cannotCreateFile))
      return
    }

    let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 200

    guard statusCode == 200 || statusCode == 206 else {
      try? FileManager.default.removeItem(at: tempURL)
      state.continuation.resume(throwing: URLError(.badServerResponse))
      return
    }

    state.continuation.resume(returning: DownloadResult(tempURL: tempURL, statusCode: statusCode))
  }
}
