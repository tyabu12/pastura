import CryptoKit
import Foundation
import Testing

@testable import Pastura

/// Tests for `URLSessionGalleryService`.
///
/// `.serialized` because MockURLProtocol shares static handler state across
/// tests. Each test sets its own handler before exercising the service.
@Suite(.serialized) struct GalleryServiceTests {

  // MARK: - Fixtures

  private static let indexURL = URL(
    // swiftlint:disable:next force_unwrapping
    string: "https://example.com/gallery.json")!
  private static let yamlURL = URL(
    // swiftlint:disable:next force_unwrapping
    string: "https://example.com/scenarios/asch.yaml")!

  private static let sampleJSON = """
    {
      "version": 1,
      "updated_at": "2026-04-14T00:00:00Z",
      "scenarios": []
    }
    """

  private func makeService(cacheDirectory: URL) -> URLSessionGalleryService {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSessionGalleryService(
      indexURL: Self.indexURL,
      cacheDirectory: cacheDirectory,
      sessionConfiguration: config)
  }

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("pastura-gallery-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private func response(
    status: Int, headers: [String: String] = [:], for url: URL = indexURL
  ) -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
  }

  // MARK: - refreshIndex

  @Test func refreshIndexFirstCallReturnsAndCachesIndex() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let jsonData = Data(Self.sampleJSON.utf8)
    MockURLProtocol.setHandler { _ in
      (self.response(status: 200, headers: ["ETag": "\"v1\""]), jsonData)
    }

    let index = try await service.refreshIndex()
    #expect(index?.version == 1)

    // Cache file written
    let cachePath = tmp.appendingPathComponent("gallery.json")
    #expect(FileManager.default.fileExists(atPath: cachePath.path))

    // ETag sidecar written
    let etagPath = tmp.appendingPathComponent("gallery.json.etag")
    let etag = try String(contentsOf: etagPath, encoding: .utf8)
    #expect(etag == "\"v1\"")
  }

  @Test func refreshIndexSendsIfNoneMatchOnSubsequentCall() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    // Prime cache with an ETag.
    let jsonData = Data(Self.sampleJSON.utf8)
    MockURLProtocol.setHandler { _ in
      (self.response(status: 200, headers: ["ETag": "\"v1\""]), jsonData)
    }
    _ = try await service.refreshIndex()

    // Next call should include the stored ETag.
    let capturedHeader = CapturedHeader()
    MockURLProtocol.setHandler { request in
      capturedHeader.set(request.value(forHTTPHeaderField: "If-None-Match"))
      return (self.response(status: 304), Data())
    }

    let result = try await service.refreshIndex()
    #expect(result == nil)
    #expect(capturedHeader.get() == "\"v1\"")
  }

  @Test func refreshIndexRejectsOversizeResponse() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    // 2 MiB payload exceeds the 1 MiB indexSizeLimit.
    let oversize = Data(repeating: 0x7B, count: 2 * 1024 * 1024)
    MockURLProtocol.setHandler { _ in (self.response(status: 200), oversize) }

    await #expect(
      throws: GalleryServiceError.responseTooLarge(
        limit: URLSessionGalleryService.indexSizeLimit)
    ) {
      _ = try await service.refreshIndex()
    }
  }

  @Test func refreshIndexRejectsCorruptedBody() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    MockURLProtocol.setHandler { _ in
      (self.response(status: 200), Data("not json".utf8))
    }

    await #expect(throws: GalleryServiceError.corruptedCache) {
      _ = try await service.refreshIndex()
    }
  }

  @Test func refreshIndexRejectsUnexpectedStatus() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    MockURLProtocol.setHandler { _ in (self.response(status: 500), Data()) }

    await #expect(throws: GalleryServiceError.unexpectedStatus(500)) {
      _ = try await service.refreshIndex()
    }
  }

  // MARK: - loadCachedIndex

  @Test func loadCachedIndexReturnsNilWhenNoCache() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let cached = try service.loadCachedIndex()
    #expect(cached == nil)
  }

  @Test func loadCachedIndexReturnsPreviouslyCachedIndex() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let jsonData = Data(Self.sampleJSON.utf8)
    MockURLProtocol.setHandler { _ in (self.response(status: 200), jsonData) }
    _ = try await service.refreshIndex()

    let cached = try service.loadCachedIndex()
    #expect(cached?.version == 1)
  }

  @Test func loadCachedIndexThrowsOnCorruptedFile() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let cachePath = tmp.appendingPathComponent("gallery.json")
    try Data("garbage".utf8).write(to: cachePath)

    #expect(throws: GalleryServiceError.corruptedCache) {
      _ = try service.loadCachedIndex()
    }
  }

  // MARK: - fetchScenarioYAML

  @Test func fetchScenarioYAMLReturnsBodyOnHashMatch() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let yaml = "id: test\nname: Test\n"
    let data = Data(yaml.utf8)
    let hash = URLSessionGalleryService.sha256Hex(data)

    MockURLProtocol.setHandler { _ in (self.response(status: 200, for: Self.yamlURL), data) }

    let result = try await service.fetchScenarioYAML(from: Self.yamlURL, expectedSHA256: hash)
    #expect(result == yaml)
  }

  @Test func fetchScenarioYAMLThrowsOnHashMismatch() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let yaml = "id: test\nname: Test\n"
    let data = Data(yaml.utf8)
    let wrongHash = String(repeating: "0", count: 64)

    MockURLProtocol.setHandler { _ in (self.response(status: 200, for: Self.yamlURL), data) }

    await #expect(
      throws: GalleryServiceError.hashMismatch(
        expected: wrongHash,
        actual: URLSessionGalleryService.sha256Hex(data))
    ) {
      _ = try await service.fetchScenarioYAML(from: Self.yamlURL, expectedSHA256: wrongHash)
    }
  }

  @Test func fetchScenarioYAMLRejectsOversizeResponse() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    // 512 KiB exceeds the 256 KiB yamlSizeLimit.
    let oversize = Data(repeating: 0x20, count: 512 * 1024)
    let hash = URLSessionGalleryService.sha256Hex(oversize)
    MockURLProtocol.setHandler { _ in (self.response(status: 200, for: Self.yamlURL), oversize) }

    await #expect(
      throws: GalleryServiceError.responseTooLarge(
        limit: URLSessionGalleryService.yamlSizeLimit)
    ) {
      _ = try await service.fetchScenarioYAML(from: Self.yamlURL, expectedSHA256: hash)
    }
  }

  // MARK: - SHA256 helper

  @Test func sha256HexMatchesKnownVector() {
    // "abc" → SHA-256 (standard test vector)
    let data = Data("abc".utf8)
    let hex = URLSessionGalleryService.sha256Hex(data)
    #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }
}

// MARK: - URLProtocol mock

/// Intercepts URLSession requests so tests can return canned responses.
///
/// The static handler is shared across all requests in the suite, which is
/// why the surrounding `@Suite` uses `.serialized`.
private final class MockURLProtocol: URLProtocol {
  typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

  private static let lock = NSLock()
  nonisolated(unsafe) private static var handler: Handler?

  static func setHandler(_ handler: @escaping Handler) {
    lock.lock()
    defer { lock.unlock() }
    self.handler = handler
  }

  static func currentHandler() -> Handler? {
    lock.lock()
    defer { lock.unlock() }
    return handler
  }

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let handler = Self.currentHandler() else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let (response, data) = handler(request)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
}

/// Thread-safe holder for a single captured value used across the async
/// URLSession delegate queue and the test thread.
private final class CapturedHeader: @unchecked Sendable {
  private let lock = NSLock()
  private var value: String?

  func set(_ value: String?) {
    lock.lock()
    defer { lock.unlock() }
    self.value = value
  }

  func get() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}
