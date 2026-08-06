import CryptoKit
import Foundation
import Testing

@testable import Pastura

// Split out of `GalleryServiceTests` to keep that file under swiftlint's
// 400-line `file_length` cap (testing.md § "Splitting a Suite Across
// Files"). Sibling-file `extension` of the same suite — NOT a new `@Suite`,
// which would run in parallel and race the shared GalleryMockURLProtocol handler.
extension GalleryServiceTests {

  // MARK: - fetchHighlightData

  @Test func fetchHighlightDataReturnsBytesOnHashMatch() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let json = "{\"excerpt\":[]}"
    let data = Data(json.utf8)
    let hash = URLSessionGalleryService.sha256Hex(data)

    GalleryMockURLProtocol.setHandler { _ in (self.response(status: 200, for: Self.yamlURL), data) }

    let result = try await service.fetchHighlightData(from: Self.yamlURL, expectedSHA256: hash)
    #expect(result == data)
  }

  @Test func fetchHighlightDataThrowsOnHashMismatch() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    let data = Data("{\"excerpt\":[]}".utf8)
    let wrongHash = String(repeating: "0", count: 64)

    GalleryMockURLProtocol.setHandler { _ in (self.response(status: 200, for: Self.yamlURL), data) }

    await #expect(
      throws: GalleryServiceError.hashMismatch(
        expected: wrongHash,
        actual: URLSessionGalleryService.sha256Hex(data))
    ) {
      _ = try await service.fetchHighlightData(from: Self.yamlURL, expectedSHA256: wrongHash)
    }
  }

  @Test func fetchHighlightDataRejectsOversizeResponse() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    // 128 KiB exceeds the 64 KiB highlightSizeLimit.
    let oversize = Data(repeating: 0x20, count: 128 * 1024)
    let hash = URLSessionGalleryService.sha256Hex(oversize)
    GalleryMockURLProtocol.setHandler { _ in (self.response(status: 200, for: Self.yamlURL), oversize) }

    await #expect(
      throws: GalleryServiceError.responseTooLarge(
        limit: URLSessionGalleryService.highlightSizeLimit)
    ) {
      _ = try await service.fetchHighlightData(from: Self.yamlURL, expectedSHA256: hash)
    }
  }

  @Test func fetchHighlightDataResolvesRelativeURLAgainstIndex() async throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let service = makeService(cacheDirectory: tmp)

    // Relative input — should be resolved against indexURL's directory.
    // swiftlint:disable:next force_unwrapping
    let relative = URL(string: "highlights/asch.json")!
    let expectedAbsolute = URL(
      // swiftlint:disable:next force_unwrapping
      string: "https://example.com/highlights/asch.json")!

    let data = Data("{\"excerpt\":[]}".utf8)
    let hash = URLSessionGalleryService.sha256Hex(data)

    let capturedURL = CapturedHeader()  // reuse as a string holder
    GalleryMockURLProtocol.setHandler { request in
      capturedURL.set(request.url?.absoluteString)
      return (self.response(status: 200, for: expectedAbsolute), data)
    }

    let result = try await service.fetchHighlightData(from: relative, expectedSHA256: hash)
    #expect(result == data)
    #expect(capturedURL.get() == expectedAbsolute.absoluteString)
  }
}
