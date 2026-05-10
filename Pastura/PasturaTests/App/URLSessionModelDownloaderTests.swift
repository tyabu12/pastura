import Foundation
import Testing

@testable import Pastura

// MARK: - URLProtocol Mock
//
// URLSession routes every request through `URLProtocol` first, so a custom
// subclass can intercept and answer requests without any real network. The
// static configuration vector means tests using this protocol must run
// serialized — see `@Suite(.serialized, ...)` below.

/// URLProtocol that captures incoming requests and answers from a configurable
/// per-test response handler. Reset state between tests via `reset()`.
///
/// Not `final` so the `class func canInit/canonicalRequest` overrides URLProtocol
/// requires don't trip swiftlint's `static_over_final_class` rule. The class
/// only lives in the test target.
class CapturingMockURLProtocol: URLProtocol, @unchecked Sendable {
  // nonisolated(unsafe) is the documented escape valve for static mutable test
  // fixtures under Swift 6 strict concurrency. Safe because tests using this
  // protocol are gated by the suite's `.serialized` trait.
  nonisolated(unsafe) static var responseProvider: (@Sendable (URLRequest) -> ResponseSpec)?
  nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

  enum ResponseSpec {
    case success(statusCode: Int, headers: [String: String], body: Data)
    case failure(NSError)
  }

  static func reset() {
    responseProvider = nil
    capturedRequests = []
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.capturedRequests.append(request)
    guard let provider = Self.responseProvider else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    switch provider(request) {
    case .success(let code, let headers, let body):
      guard let url = request.url,
        let response = HTTPURLResponse(
          url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let err):
      client?.urlProtocol(self, didFailWithError: err)
    }
  }

  override func stopLoading() {}
}

// MARK: - Tests

@Suite("URLSessionModelDownloader", .serialized, .timeLimit(.minutes(1)))
struct URLSessionModelDownloaderTests {

  // MARK: updateResumeDataFromError (cache lifecycle, pure logic)

  @Test("updateResumeDataFromError stores blob when error has NSURLSessionDownloadTaskResumeData")
  func updateResumeDataFromErrorStoresBlob() {
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!
    let blob = Data("opaque-resume-blob".utf8)
    let error = NSError(
      domain: NSURLErrorDomain,
      code: NSURLErrorTimedOut,
      userInfo: [NSURLSessionDownloadTaskResumeData: blob]
    )

    downloader.updateResumeDataFromError(error, for: url)

    #expect(downloader.cachedResumeData(for: url) == blob)
  }

  @Test(
    "updateResumeDataFromError leaves cache empty when error lacks resumeData and no prior blob")
  func updateResumeDataFromErrorNoBlobNoPrior() {
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!
    let error = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [:])

    downloader.updateResumeDataFromError(error, for: url)

    #expect(downloader.cachedResumeData(for: url) == nil)
  }

  @Test(
    "updateResumeDataFromError clears stale prior blob when error lacks fresh resumeData"
  )
  func updateResumeDataFromErrorClearsStaleOnNonResumableError() {
    // Scenario: attempt 1 timed out with resumeData → blob A cached. Attempt 2
    // failed with a non-resumable error (e.g., 5xx, DNS, badServerResponse) so
    // Apple did not supply a fresh blob. Blob A's referenced URLSession temp
    // file was consumed by attempt 2 and is now invalid; passing A to
    // `downloadTask(withResumeData:)` on attempt 3 would fail at decode-time.
    // The cache must be cleared so attempt 3 starts fresh.
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!

    let blobA = Data("blob-A".utf8)
    downloader.updateResumeDataFromError(
      NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: blobA]),
      for: url)
    #expect(downloader.cachedResumeData(for: url) == blobA)

    // Attempt 2 — error without resumeData. Should clear blob A.
    downloader.updateResumeDataFromError(
      NSError(
        domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [:]),
      for: url)

    #expect(downloader.cachedResumeData(for: url) == nil)
  }

  @Test("updateResumeDataFromError overwrites prior blob for same URL (last wins)")
  func updateResumeDataFromErrorLastWins() {
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!

    let first = Data("first".utf8)
    let second = Data("second".utf8)

    downloader.updateResumeDataFromError(
      NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: first]),
      for: url)
    downloader.updateResumeDataFromError(
      NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: second]),
      for: url)

    #expect(downloader.cachedResumeData(for: url) == second)
  }

  @Test("updateResumeDataFromError scopes by URL (different URLs are independent)")
  func updateResumeDataFromErrorScopesByURL() {
    let downloader = URLSessionModelDownloader()
    let urlA = URL(string: "https://example.com/a.gguf")!
    let urlB = URL(string: "https://example.com/b.gguf")!

    let blobA = Data("blobA".utf8)
    let blobB = Data("blobB".utf8)

    downloader.updateResumeDataFromError(
      NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: blobA]),
      for: urlA)
    downloader.updateResumeDataFromError(
      NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: blobB]),
      for: urlB)

    #expect(downloader.cachedResumeData(for: urlA) == blobA)
    #expect(downloader.cachedResumeData(for: urlB) == blobB)
  }

  // MARK: download() integration via URLProtocol

  @Test("explicit resumeOffset sends Range header (legacy fallback path)")
  func resumeOffsetSendsRangeHeader() async throws {
    CapturingMockURLProtocol.reset()
    defer { CapturingMockURLProtocol.reset() }

    CapturingMockURLProtocol.responseProvider = { _ in
      .success(
        statusCode: 206,
        headers: [
          "Content-Length": "500",
          "Content-Range": "bytes 500-999/1000"
        ],
        body: Data(repeating: 0x43, count: 500)
      )
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)

    let url = URL(string: "https://example.com/model.gguf")!
    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    try Data(repeating: 0x42, count: 500).write(to: dest)
    defer { try? FileManager.default.removeItem(at: dest) }

    try await downloader.download(
      from: url, resumeOffset: 500, to: dest, progressHandler: { _, _ in })

    let request = CapturingMockURLProtocol.capturedRequests.first
    #expect(request?.value(forHTTPHeaderField: "Range") == "bytes=500-")

    let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
    #expect((attrs[.size] as? Int64) == 1000)
  }

  @Test("successful download does not spuriously populate the cache")
  func successDoesNotPopulateCache() async throws {
    // We cannot directly test "cache cleared on success" by pre-seeding the
    // cache with a fake blob: `downloadTask(withResumeData:)` rejects bogus
    // blobs before URLProtocol gets a chance to intercept, so the success
    // branch is unreachable from a seeded-cache state in unit tests. Instead
    // verify the related invariant: a clean successful download leaves the
    // cache empty (no accidental population). The clear-on-success branch
    // itself is a one-line assignment verified by inspection.
    CapturingMockURLProtocol.reset()
    defer { CapturingMockURLProtocol.reset() }

    CapturingMockURLProtocol.responseProvider = { _ in
      .success(
        statusCode: 200,
        headers: ["Content-Length": "100"],
        body: Data(repeating: 0x42, count: 100)
      )
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)

    let url = URL(string: "https://example.com/model.gguf")!
    #expect(downloader.cachedResumeData(for: url) == nil)

    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    defer { try? FileManager.default.removeItem(at: dest) }

    try await downloader.download(
      from: url, resumeOffset: 0, to: dest, progressHandler: { _, _ in })

    #expect(downloader.cachedResumeData(for: url) == nil)
  }

  @Test("error path captures resumeData when URLSession populates userInfo")
  func errorPathCapturesResumeData() async throws {
    CapturingMockURLProtocol.reset()
    defer { CapturingMockURLProtocol.reset() }

    let injectedBlob = Data("fake-resume-blob".utf8)
    CapturingMockURLProtocol.responseProvider = { _ in
      // Simulate Apple's behavior: transient error with resumeData attached.
      // In production this happens automatically when a partial 200-OK response
      // followed by a connection drop satisfies URLSession's heuristics; mocking
      // it directly via NSError lets us verify our capture wiring.
      .failure(
        NSError(
          domain: NSURLErrorDomain,
          code: NSURLErrorTimedOut,
          userInfo: [NSURLSessionDownloadTaskResumeData: injectedBlob]
        ))
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)

    let url = URL(string: "https://example.com/model.gguf")!
    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    defer { try? FileManager.default.removeItem(at: dest) }

    await #expect(throws: (any Error).self) {
      try await downloader.download(
        from: url, resumeOffset: 0, to: dest, progressHandler: { _, _ in })
    }

    #expect(downloader.cachedResumeData(for: url) == injectedBlob)
  }

  @Test("206 with missing destination throws (precondition guard)")
  func partialContentMissingDestinationThrows() async throws {
    CapturingMockURLProtocol.reset()
    defer { CapturingMockURLProtocol.reset() }

    // 206 partial-content with `resumeOffset > 0` but no pre-existing
    // destination file. Unreachable from current production callers
    // (`ModelManager.performDownload` computes `resumeOffset` only when
    // `partialURL` exists); the precondition guard surfaces it as an
    // explicit throw rather than silently writing a head-truncated file.
    // Regression target for any future cross-session resume work.
    CapturingMockURLProtocol.responseProvider = { _ in
      .success(
        statusCode: 206,
        headers: [
          "Content-Length": "500",
          "Content-Range": "bytes 500-999/1000"
        ],
        body: Data(repeating: 0x43, count: 500)
      )
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)

    let url = URL(string: "https://example.com/model.gguf")!
    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    // Intentionally NOT pre-writing dest — exercises the missing-destination guard.
    defer { try? FileManager.default.removeItem(at: dest) }

    do {
      try await downloader.download(
        from: url, resumeOffset: 500, to: dest, progressHandler: { _, _ in })
      Issue.record("expected throw on 206 + missing destination, but download succeeded")
    } catch let urlError as URLError {
      #expect(urlError.code == .badServerResponse)
    } catch {
      Issue.record("expected URLError, got \(type(of: error)): \(error)")
    }

    // Verify no head-truncated file was left behind.
    #expect(!FileManager.default.fileExists(atPath: dest.path))
  }

  @Test("206 stream-append handles multi-buffer body (boundary + tail)")
  func partialContentStreamingMultiBuffer() async throws {
    CapturingMockURLProtocol.reset()
    defer { CapturingMockURLProtocol.reset() }

    // Body sized at 2.5 MB so the streaming loop hits all three cases:
    //   read 1: 1 MB full chunk
    //   read 2: 1 MB full chunk
    //   read 3: 0.5 MB tail partial chunk
    //   read 4: empty → loop terminator
    // Pre-existing destination bytes use 0x42; new body uses 0x43.
    // Asserting both halves catches a missing `seekToEndOfFile` (would
    // overwrite the head bytes with 0x43 instead of appending after them).
    let preExisting = 500
    let bodySize = 2_500_000
    let body = Data(repeating: 0x43, count: bodySize)

    CapturingMockURLProtocol.responseProvider = { _ in
      .success(
        statusCode: 206,
        headers: [
          "Content-Length": "\(bodySize)",
          "Content-Range":
            "bytes \(preExisting)-\(preExisting + bodySize - 1)/\(preExisting + bodySize)"
        ],
        body: body
      )
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)

    let url = URL(string: "https://example.com/model.gguf")!
    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    try Data(repeating: 0x42, count: preExisting).write(to: dest)
    defer { try? FileManager.default.removeItem(at: dest) }

    try await downloader.download(
      from: url, resumeOffset: Int64(preExisting), to: dest, progressHandler: { _, _ in })

    let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
    #expect((attrs[.size] as? Int64) == Int64(preExisting + bodySize))

    // Spot-check head (preserved pre-existing 0x42) and tail (new body 0x43).
    let written = try Data(contentsOf: dest)
    #expect(written.prefix(preExisting) == Data(repeating: 0x42, count: preExisting))
    #expect(written.suffix(bodySize) == body)
  }
}
