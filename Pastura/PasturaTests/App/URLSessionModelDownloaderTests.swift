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
final class CapturingMockURLProtocol: URLProtocol, @unchecked Sendable {
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

  // MARK: captureResumeData (cache lifecycle, pure logic)

  @Test("captureResumeData stores blob when error has NSURLSessionDownloadTaskResumeData")
  func captureResumeDataStoresBlob() {
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!
    let blob = Data("opaque-resume-blob".utf8)
    let error = NSError(
      domain: NSURLErrorDomain,
      code: NSURLErrorTimedOut,
      userInfo: [NSURLSessionDownloadTaskResumeData: blob]
    )

    downloader.captureResumeData(from: error, for: url)

    #expect(downloader.cachedResumeData(for: url) == blob)
  }

  @Test("captureResumeData no-ops when error lacks resumeData userInfo key")
  func captureResumeDataNoOpsWithoutKey() {
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!
    let error = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [:])

    downloader.captureResumeData(from: error, for: url)

    #expect(downloader.cachedResumeData(for: url) == nil)
  }

  @Test("captureResumeData overwrites prior blob for same URL (last wins)")
  func captureResumeDataLastWins() {
    let downloader = URLSessionModelDownloader()
    let url = URL(string: "https://example.com/model.gguf")!

    let first = Data("first".utf8)
    let second = Data("second".utf8)

    downloader.captureResumeData(
      from: NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: first]),
      for: url)
    downloader.captureResumeData(
      from: NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: second]),
      for: url)

    #expect(downloader.cachedResumeData(for: url) == second)
  }

  @Test("captureResumeData scopes by URL (different URLs are independent)")
  func captureResumeDataScopesByURL() {
    let downloader = URLSessionModelDownloader()
    let urlA = URL(string: "https://example.com/a.gguf")!
    let urlB = URL(string: "https://example.com/b.gguf")!

    let blobA = Data("blobA".utf8)
    let blobB = Data("blobB".utf8)

    downloader.captureResumeData(
      from: NSError(
        domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
        userInfo: [NSURLSessionDownloadTaskResumeData: blobA]),
      for: urlA)
    downloader.captureResumeData(
      from: NSError(
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
}
