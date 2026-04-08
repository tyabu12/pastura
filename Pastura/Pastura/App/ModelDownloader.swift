import Foundation

/// Abstraction over URLSession download for testability.
///
/// Production implementation streams bytes to disk via `URLSession.shared`.
/// Test doubles return immediately with a local file URL.
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

/// Production downloader using `URLSession.shared.bytes(for:)`.
///
/// Streams the response body as `AsyncBytes` and writes chunks to disk.
/// Supports resume via HTTP Range headers.
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

    let (bytes, response) = try await session.bytes(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    let statusCode = httpResponse.statusCode
    guard statusCode == 200 || statusCode == 206 else {
      throw URLError(.badServerResponse)
    }

    // Total expected bytes from Content-Length (or -1 if unknown)
    let contentLength = httpResponse.expectedContentLength
    let totalBytes: Int64 =
      if contentLength > 0 {
        statusCode == 206 ? resumeOffset + contentLength : contentLength
      } else {
        -1
      }

    // Open file handle — truncate if full response (200), append if partial (206)
    let fileManager = FileManager.default
    if statusCode == 200 {
      // Server ignored Range or this is a fresh download — start from scratch
      fileManager.createFile(atPath: destination.path, contents: nil)
    } else if !fileManager.fileExists(atPath: destination.path) {
      fileManager.createFile(atPath: destination.path, contents: nil)
    }

    let fileHandle = try FileHandle(forWritingTo: destination)
    if statusCode == 206 {
      fileHandle.seekToEndOfFile()
    }

    defer { try? fileHandle.close() }

    var bytesReceived: Int64 = statusCode == 206 ? resumeOffset : 0
    // Buffer size: 256 KB chunks for progress reporting
    let bufferSize = 256 * 1024
    var buffer = Data(capacity: bufferSize)

    for try await byte in bytes {
      buffer.append(byte)

      if buffer.count >= bufferSize {
        fileHandle.write(buffer)
        bytesReceived += Int64(buffer.count)
        buffer.removeAll(keepingCapacity: true)
        progressHandler(bytesReceived, totalBytes)
      }
    }

    // Flush remaining bytes
    if !buffer.isEmpty {
      fileHandle.write(buffer)
      bytesReceived += Int64(buffer.count)
      progressHandler(bytesReceived, totalBytes)
    }

    return statusCode
  }
}
