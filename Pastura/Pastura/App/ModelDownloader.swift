import Foundation

/// Abstraction over URLSession download for testability.
///
/// Production implementation uses `URLSession.download(for:)` with a delegate
/// for progress reporting. Test doubles return immediately with a local file URL.
protocol ModelDownloader: Sendable {
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

/// Production downloader using `URLSession.download(for:delegate:)`.
///
/// Downloads to a temporary file, then moves it to the destination.
/// Uses a `URLSessionDownloadDelegate` for progress reporting — avoids the
/// byte-by-byte overhead of `AsyncBytes` iteration on multi-GB files.
final class URLSessionModelDownloader: ModelDownloader, @unchecked Sendable {
  // @unchecked Sendable: URLSession.shared is thread-safe.
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
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

    let delegate = ProgressDelegate(
      resumeOffset: resumeOffset,
      progressHandler: progressHandler
    )
    let (tempURL, response) = try await session.download(for: request, delegate: delegate)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    let statusCode = httpResponse.statusCode
    guard statusCode == 200 || statusCode == 206 else {
      throw URLError(.badServerResponse)
    }

    let fileManager = FileManager.default

    if statusCode == 200 || resumeOffset == 0 {
      // Full download — replace destination entirely
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

// MARK: - Progress Delegate

/// Reports download progress via a callback. Passed as the delegate to
/// `URLSession.download(for:delegate:)`.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
  let resumeOffset: Int64
  let progressHandler: @Sendable (Int64, Int64) -> Void

  init(
    resumeOffset: Int64,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) {
    self.resumeOffset = resumeOffset
    self.progressHandler = progressHandler
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let received = resumeOffset + totalBytesWritten
    let total =
      totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown
      ? resumeOffset + totalBytesExpectedToWrite : -1
    progressHandler(received, total)
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // Required by URLSessionDownloadDelegate protocol.
    // File handling is done in the async download() call above.
  }
}
