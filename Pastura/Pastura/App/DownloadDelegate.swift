import Foundation

// MARK: - Download Result

/// Value returned from `DownloadDelegate` to `URLSessionModelDownloader`'s
/// continuation. Internal-by-default (was `private` in `ModelDownloader.swift`
/// before the file was split for `file_length` cap; sibling-file access
/// requires module-internal visibility).
struct DownloadResult: Sendable {
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
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
