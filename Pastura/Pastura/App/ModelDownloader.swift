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
  /// - Returns: The HTTP status code (206 for partial, 200 for full).
  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws -> Int
}

/// Production downloader using delegate-based `URLSession` + `URLSessionDownloadTask`.
///
/// The async `URLSession.download(for:delegate:)` API does not reliably deliver
/// `URLSessionDownloadDelegate` callbacks (didWriteData, didFinishDownloadingTo)
/// to per-request delegates. This implementation creates a dedicated session with
/// a session-level delegate and bridges completion back to async/await via
/// `CheckedContinuation`.
final class URLSessionModelDownloader: ModelDownloader, @unchecked Sendable {
  // @unchecked Sendable: no mutable state after init.
  private let sessionConfiguration: URLSessionConfiguration

  init(sessionConfiguration: URLSessionConfiguration = .default) {
    self.sessionConfiguration = sessionConfiguration
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws -> Int {
    var request = URLRequest(url: url)
    if resumeOffset > 0 {
      request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
    }

    // Thread-safe holder so onCancel can reach the URLSessionDownloadTask.
    // Swift Task cancellation does NOT propagate to URLSession automatically —
    // we must cancel the download task explicitly.
    let taskHolder = OSAllocatedUnfairLock<URLSessionDownloadTask?>(initialState: nil)

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
        let downloadTask = session.downloadTask(with: request)
        delegate.task = downloadTask
        taskHolder.withLock { $0 = downloadTask }
        downloadTask.resume()
      }
    } onCancel: {
      // Cancel the URLSession task, which triggers didCompleteWithError
      // with NSURLErrorCancelled, resuming the continuation with an error.
      taskHolder.withLock { $0?.cancel() }
    }

    // File handling (after continuation resumes, on the caller's executor)
    let statusCode = result.statusCode
    let tempURL = result.tempURL
    let fileManager = FileManager.default

    if statusCode == 200 || resumeOffset == 0 {
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: tempURL, to: destination)
    } else {
      // Partial content (206) — append downloaded chunk to existing file
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

    return statusCode
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
