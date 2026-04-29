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
///
/// ## Known limitation: iOS network-warmup pause on Wi-Fi/Airplane toggle
///
/// After the user toggles Wi-Fi or Airplane Mode OFF → ON to recover from a
/// download interruption, tapping Retry produces a 3-5 second visible
/// "freeze" on the progress UI before bytes start arriving. The freeze does
/// **not** occur after device sleep stops a download — that distinction is
/// the diagnostic signal pointing at the cause. Observed during PR #278
/// device QA.
///
/// Root cause is not in this code path. iOS reinitializes the network stack
/// on Wi-Fi/Airplane toggle (DHCP, DNS resolver re-init, captive-portal
/// probe to `captive.apple.com`). During warmup, all outbound connections —
/// including this downloader's `URLSessionDownloadTask` — are queued at the
/// system level until iOS confirms internet availability. Sleep preserves
/// network state, so wake-up doesn't trigger this warmup. Pastura's main
/// thread stays responsive throughout (the UI just has nothing to show
/// because the `ModelManager.performDownload` `.downloading(0.0)`
/// placeholder is already on screen and no `didWriteData` callbacks have
/// arrived yet).
///
/// **Accepted as iOS-side behavior; not actionable from app code.** If the
/// UX cost grows, candidate improvements (out of scope for #278; track in
/// a future Issue when revisiting):
///
/// - PromoCard "再接続中…" hint between retry tap and first progress
///   sample (requires a new state plumbed from this downloader signalling
///   "URLSession.resume() called, no bytes yet").
/// - Skip the `.downloading(0.0)` placeholder in
///   `ModelManager.performDownload` and stay in `.error` until the first
///   real progress sample arrives — at the cost of the Retry button
///   appearing inert for 3-5 seconds.
nonisolated final class URLSessionModelDownloader: ModelDownloader, @unchecked Sendable {
  // @unchecked Sendable: `sessionConfiguration` is set once at init and never
  // mutated; `resumeDataCache` is guarded by `OSAllocatedUnfairLock`.
  private let sessionConfiguration: URLSessionConfiguration

  /// Per-URL in-memory cache of `NSURLSessionDownloadTaskResumeData` blobs.
  /// Populated on transient error (when Apple supplies resumeData), cleared on
  /// successful download.
  private let resumeDataCache: OSAllocatedUnfairLock<[URL: Data]> = .init(initialState: [:])

  /// `.notice`-level logger kept in release builds so the resume-path
  /// telemetry (cache populate vs. miss, blob size, error domain/code,
  /// completion status code) survives in Console.app for QA + future
  /// regression checks. The events are infrequent (one per download
  /// attempt + one per failure) so log volume is negligible.
  ///
  /// All interpolations are diagnostic primitives (URL, byte count,
  /// integer code) — no user content per `CLAUDE.md` Logger-privacy rule.
  /// Filter in Console.app:
  /// `subsystem:com.tyabu12.Pastura category:ModelDownloader`.
  private static let logger = Logger(
    subsystem: "com.tyabu12.Pastura", category: "ModelDownloader")

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
    logDownloadStart(
      url: url, resumeOffset: resumeOffset, cachedBlobSize: cachedResumeData?.count)

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

      Self.logger.notice(
        """
        download success url=\(url.absoluteString, privacy: .public) \
        statusCode=\(result.statusCode, privacy: .public) \
        resumeOffset=\(resumeOffset, privacy: .public)
        """)

      try mergeIntoDestination(
        result: result, resumeOffset: resumeOffset, destination: destination)
    } catch {
      captureResumeData(from: error, for: url)
      throw error
    }
  }

  /// Emits a `.notice`-level entry log identifying which of the three resume
  /// paths the current call is taking. Extracted from `download(...)` to keep
  /// that function under swiftlint's `function_body_length` cap.
  private func logDownloadStart(url: URL, resumeOffset: Int64, cachedBlobSize: Int?) {
    let path: String =
      cachedBlobSize != nil
      ? "withResumeData"
      : (resumeOffset > 0 ? "rangeHeader" : "fresh")
    Self.logger.notice(
      """
      download start url=\(url.absoluteString, privacy: .public) \
      resumeOffset=\(resumeOffset, privacy: .public) \
      cachedBlob=\(cachedBlobSize ?? -1, privacy: .public)bytes \
      path=\(path, privacy: .public)
      """)
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

  /// Updates the per-URL resumeData cache from a thrown error.
  ///
  /// - When the error's `userInfo` contains `NSURLSessionDownloadTaskResumeData`,
  ///   the fresh blob is stored — Apple has signalled that the partial bytes
  ///   are still resumable.
  /// - Otherwise the existing entry for `url` is cleared. Any prior cached
  ///   blob references a URLSession temp file that the just-completed attempt
  ///   has invalidated; passing it to `downloadTask(withResumeData:)` on the
  ///   next retry would fail at decode-time. Clearing forces a clean restart.
  ///
  /// Extracted for unit-testability — production callers only invoke this
  /// from the `catch` block in `download(...)`. Tests construct an `NSError`
  /// with a known resumeData blob to verify cache lifecycle without depending
  /// on Apple's internal heuristic for when resumeData is populated.
  func captureResumeData(from error: any Error, for url: URL) {
    let nsError = error as NSError
    let fresh = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    Self.logger.notice(
      """
      captureResumeData url=\(url.absoluteString, privacy: .public) \
      freshBlob=\(fresh?.count ?? -1, privacy: .public)bytes \
      errorDomain=\(nsError.domain, privacy: .public) \
      errorCode=\(nsError.code, privacy: .public)
      """)
    resumeDataCache.withLock { $0[url] = fresh }
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
