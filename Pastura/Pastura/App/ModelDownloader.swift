import Foundation
import os

/// Abstraction over URLSession download for testability.
///
/// Production implementation uses a delegate-based `URLSession` with
/// `URLSessionDownloadTask` for reliable progress reporting.
/// Test doubles return immediately with a local file URL.
public protocol ModelDownloader: Sendable {
  /// Downloads a file from `url` to a local temporary path.
  ///
  /// - Parameters:
  ///   - url: The remote URL to download from.
  ///   - resumeOffset: Byte offset for resuming an interrupted download (Range header).
  ///   - destination: The local file path to write to (caller manages temp naming).
  ///   - progressHandler: Called periodically with (bytesWritten, totalBytes).
  ///     `totalBytes` is -1 if the server did not provide Content-Length.
  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws
}

/// Production downloader using delegate-based `URLSession` + `URLSessionDownloadTask`.
///
/// The async `URLSession.download(for:delegate:)` API does not reliably deliver
/// `URLSessionDownloadDelegate` callbacks (didWriteData, didFinishDownloadingTo)
/// to per-request delegates. This implementation creates a dedicated session with
/// a session-level delegate and bridges completion back to async/await via
/// `CheckedContinuation`.
///
/// ## Resume after transient errors
///
/// On transient failures (timeout, lost connection mid-transfer), Apple's
/// `URLSession` populates `(error as NSError).userInfo[NSURLSessionDownloadTaskResumeData]`
/// with an opaque blob that can be passed to `downloadTask(withResumeData:)` to
/// continue from the byte position where the prior attempt stopped. This class
/// caches that blob in memory (per-URL) for the lifetime of the downloader so an
/// in-process retry resumes — the URL protocol's internal byte-position tracking
/// + ETag validation are preserved transparently.
///
/// **Out of scope:** cross-session resume (cache is in-memory only). If the user
/// force-kills the app mid-download, the next launch starts from byte zero. See
/// Issue #275 for the follow-up that would persist the blob to disk.
///
/// ## Actor isolation
///
/// `nonisolated` at type level so the synchronous accessors (`captureResumeData`,
/// `cachedResumeData`) can be invoked from any executor. Without this, the
/// project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would bind the class
/// to MainActor and break tests that exercise the cache lifecycle from the
/// non-isolated test context. The `download(...) async throws` method was
/// unaffected before adding sync accessors because the `async` hop conceals
/// the binding; the new synchronous accessors are not.
nonisolated final class URLSessionModelDownloader: ModelDownloader, @unchecked Sendable {
  // @unchecked Sendable: `sessionConfiguration` is set once at init and never
  // mutated; `resumeDataCache` is guarded by `OSAllocatedUnfairLock`.
  private let sessionConfiguration: URLSessionConfiguration

  /// Per-URL in-memory cache of `NSURLSessionDownloadTaskResumeData` blobs.
  /// Populated on transient error (when Apple supplies resumeData), cleared on
  /// successful download.
  private let resumeDataCache: OSAllocatedUnfairLock<[URL: Data]> = .init(initialState: [:])

  init(sessionConfiguration: URLSessionConfiguration = .default) {
    self.sessionConfiguration = sessionConfiguration
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws {
    let cachedResumeData = resumeDataCache.withLock { $0[url] }

    // Thread-safe holder so onCancel can reach the URLSessionDownloadTask.
    // Swift Task cancellation does NOT propagate to URLSession automatically —
    // we must cancel the download task explicitly.
    let taskHolder = OSAllocatedUnfairLock<URLSessionDownloadTask?>(initialState: nil)

    do {
      let result: DownloadResult = try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let delegate = DownloadDelegate(
            resumeOffset: resumeOffset,
            progressHandler: progressHandler,
            continuation: continuation
          )
          let session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
          )
          delegate.session = session

          let downloadTask: URLSessionDownloadTask
          if let resumeData = cachedResumeData {
            // Resume via OS-managed blob. URLSession decodes the blob to recover
            // the prior partial-file location, ETag, and byte offset, and sends
            // the Range header internally — preserving Apple's HTTP-layer
            // correctness (If-Range validation, server-side range support
            // negotiation) instead of reimplementing it ourselves.
            downloadTask = session.downloadTask(withResumeData: resumeData)
          } else {
            var request = URLRequest(url: url)
            if resumeOffset > 0 {
              // Fallback path: explicit Range header. Used when the in-memory
              // resumeData cache is empty but the on-disk partial file (.download)
              // already has bytes — typically after a fresh app launch where the
              // cache hasn't been populated yet. Test mocks also exercise this
              // path because they don't produce real `NSURLSessionDownloadTaskResumeData`.
              request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
            }
            downloadTask = session.downloadTask(with: request)
          }
          delegate.task = downloadTask
          taskHolder.withLock { $0 = downloadTask }
          downloadTask.resume()
        }
      } onCancel: {
        // Cancel the URLSession task, which triggers didCompleteWithError
        // with NSURLErrorCancelled, resuming the continuation with an error.
        taskHolder.withLock { $0?.cancel() }
      }

      // Success — clear the cache for this URL so a fresh subsequent download
      // (e.g., re-download after delete) starts cleanly.
      resumeDataCache.withLock { $0[url] = nil }

      try mergeIntoDestination(
        result: result, resumeOffset: resumeOffset, destination: destination)
    } catch {
      captureResumeData(from: error, for: url)
      throw error
    }
  }

  /// Moves or appends the URLSession-staged temp file into `destination`.
  ///
  /// With `withResumeData`, URLSession internally stitches resumed chunks into
  /// a single complete file, so the result is delivered as 200-OK semantically
  /// and falls into the truncate-and-move branch. The 206/append branch
  /// remains for the explicit Range-header fallback (cache miss with
  /// `resumeOffset > 0`).
  private func mergeIntoDestination(
    result: DownloadResult, resumeOffset: Int64, destination: URL
  ) throws {
    let fileManager = FileManager.default
    let tempURL = result.tempURL

    if result.statusCode == 200 || resumeOffset == 0 {
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: tempURL, to: destination)
      return
    }
    // Partial content (206) — append downloaded chunk to existing file.
    let downloadedData = try Data(contentsOf: tempURL)
    if fileManager.fileExists(atPath: destination.path) {
      let fileHandle = try FileHandle(forWritingTo: destination)
      fileHandle.seekToEndOfFile()
      fileHandle.write(downloadedData)
      try fileHandle.close()
    } else {
      try downloadedData.write(to: destination)
    }
    try? fileManager.removeItem(at: tempURL)
  }

  /// Captures any `NSURLSessionDownloadTaskResumeData` Apple attached to the
  /// thrown error into the in-memory cache, keyed by `url`.
  ///
  /// Extracted for unit-testability — production callers should only invoke
  /// this from the `catch` block in `download(...)`. Tests construct an
  /// `NSError` with a known resumeData blob to verify cache lifecycle without
  /// depending on Apple's internal heuristic for when resumeData is populated.
  func captureResumeData(from error: any Error, for url: URL) {
    let nsError = error as NSError
    guard let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    else { return }
    resumeDataCache.withLock { $0[url] = data }
  }

  /// Test-only: inspect cached resumeData for a URL.
  func cachedResumeData(for url: URL) -> Data? {
    resumeDataCache.withLock { $0[url] }
  }
}

// MARK: - Download Result

/// Value returned from the delegate via continuation.
private struct DownloadResult: Sendable {
  let tempURL: URL
  let statusCode: Int
}

// MARK: - Download Delegate

/// Session-level delegate that handles progress, completion, and error reporting.
///
/// Continuation is resumed exactly once, in `didCompleteWithError`:
/// - On success: `didFinishDownloadingTo` saves the temp URL, then
///   `didCompleteWithError(nil)` resumes with the result.
/// - On failure: `didCompleteWithError(error)` resumes with the error.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  // @unchecked Sendable: mutable state accessed only from URLSession's serial delegate queue,
  // except `task` which is set once before resume() and read only for cancellation.
  let resumeOffset: Int64
  let progressHandler: @Sendable (Int64, Int64) -> Void
  private var continuation: CheckedContinuation<DownloadResult, any Error>?
  private var downloadedFileURL: URL?

  /// Held to prevent session deallocation during download.
  var session: URLSession?
  /// Held for cancellation support.
  var task: URLSessionDownloadTask?

  init(
    resumeOffset: Int64,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void,
    continuation: CheckedContinuation<DownloadResult, any Error>
  ) {
    self.resumeOffset = resumeOffset
    self.progressHandler = progressHandler
    self.continuation = continuation
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let received = resumeOffset + totalBytesWritten
    let total: Int64 =
      totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown
      ? resumeOffset + totalBytesExpectedToWrite : -1
    progressHandler(received, total)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // The file at `location` is deleted after this method returns.
    // Copy it to a stable temp path so the continuation can use it.
    let tempCopy = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".gguf.tmp")
    do {
      try FileManager.default.moveItem(at: location, to: tempCopy)
      downloadedFileURL = tempCopy
    } catch {
      downloadedFileURL = nil
    }
  }

  // MARK: - URLSessionTaskDelegate

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    defer {
      // Always invalidate the session to prevent resource leaks.
      self.session?.finishTasksAndInvalidate()
      self.session = nil
    }

    if let error {
      continuation?.resume(throwing: error)
      continuation = nil
      return
    }

    // Success path
    guard let tempURL = downloadedFileURL else {
      continuation?.resume(
        throwing: URLError(.cannotCreateFile)
      )
      continuation = nil
      return
    }

    let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 200

    guard statusCode == 200 || statusCode == 206 else {
      // Clean up temp file for unexpected status codes
      try? FileManager.default.removeItem(at: tempURL)
      continuation?.resume(throwing: URLError(.badServerResponse))
      continuation = nil
      return
    }

    continuation?.resume(returning: DownloadResult(tempURL: tempURL, statusCode: statusCode))
    continuation = nil
  }
}
