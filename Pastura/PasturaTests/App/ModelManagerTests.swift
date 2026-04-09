import CryptoKit
import Foundation
import Testing

@testable import Pastura

// MARK: - Mock

/// A test double for `ModelDownloader` that returns immediately or throws.
struct MockModelDownloader: ModelDownloader, Sendable {
  let result: @Sendable () throws -> Int
  let simulateBytes: Int64

  init(
    statusCode: Int = 200,
    simulateBytes: Int64 = 1000
  ) {
    self.result = { statusCode }
    self.simulateBytes = simulateBytes
  }

  init(error: any Error) {
    self.result = { throw error }
    self.simulateBytes = 0
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws -> Int {
    let statusCode = try result()
    // Write dummy bytes to the destination to simulate a completed download
    let data = Data(repeating: 0x42, count: Int(simulateBytes))
    try data.write(to: destination)
    progressHandler(simulateBytes, simulateBytes)
    return statusCode
  }
}

// MARK: - Tests

// Download tests share filesystem paths (Documents directory), so serialize to avoid races.
@Suite("ModelManager", .serialized)
@MainActor
struct ModelManagerTests {

  private func makeSUT(
    downloader: any ModelDownloader = MockModelDownloader(),
    physicalMemory: UInt64 = 8 * 1024 * 1024 * 1024,
    expectedFileSize: Int64 = 0,
    expectedSHA256: String? = nil
  ) -> ModelManager {
    ModelManager(
      downloader: downloader,
      fileManager: .default,
      physicalMemory: physicalMemory,
      expectedFileSize: expectedFileSize,
      expectedSHA256: expectedSHA256
    )
  }

  // MARK: - Device Check

  @Test("checkModelStatus sets unsupportedDevice when RAM < 7 GB threshold")
  func unsupportedDevice() {
    // 5.5 GB simulates what iOS reports on a 6 GB device
    let sut = makeSUT(physicalMemory: 5_500_000_000)
    sut.checkModelStatus()
    #expect(sut.state == .unsupportedDevice)
  }

  @Test("checkModelStatus sets notDownloaded when model file does not exist")
  func modelNotDownloaded() {
    let sut = makeSUT()
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)
  }

  @Test("checkModelStatus sets ready when model file exists")
  func modelReady() {
    let sut = makeSUT()

    // Place a dummy file at the model path
    let modelPath = sut.modelFileURL
    FileManager.default.createFile(atPath: modelPath.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: modelPath) }

    sut.checkModelStatus()
    #expect(sut.state == .ready(modelPath: modelPath.path))
  }

  // MARK: - Download

  @Test("downloadModel transitions from notDownloaded to ready on success")
  func downloadSuccess() async {
    let sut = makeSUT(
      downloader: MockModelDownloader(statusCode: 200, simulateBytes: 100)
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    if case .ready = sut.state {
      // Success
    } else {
      Issue.record("Expected .ready but got \(sut.state)")
    }
  }

  @Test("downloadModel transitions to error on download failure")
  func downloadFailure() async {
    let sut = makeSUT(
      downloader: MockModelDownloader(error: URLError(.notConnectedToInternet))
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    await sut.downloadModel()

    if case .error = sut.state {
      // Expected
    } else {
      Issue.record("Expected .error but got \(sut.state)")
    }
  }

  @Test("downloadModel is no-op when state is unsupportedDevice")
  func downloadNoOpWhenUnsupported() async {
    let sut = makeSUT(physicalMemory: 4 * 1024 * 1024 * 1024)
    sut.checkModelStatus()
    #expect(sut.state == .unsupportedDevice)

    await sut.downloadModel()
    #expect(sut.state == .unsupportedDevice)
  }

  @Test("downloadModel retries from error state")
  func downloadRetryFromError() async {
    let sut = makeSUT(downloader: MockModelDownloader(error: URLError(.timedOut)))
    sut.checkModelStatus()
    await sut.downloadModel()

    guard case .error = sut.state else {
      Issue.record("Expected .error after first download attempt")
      return
    }

    // Second call also fails (same downloader), but verifies it proceeds from .error
    await sut.downloadModel()
    if case .error = sut.state {
      // Expected
    } else {
      Issue.record("Expected .error on retry with failing downloader")
    }
  }

  // MARK: - Delete

  @Test("deleteModel removes files and sets state to notDownloaded")
  func deleteModel() {
    let sut = makeSUT()

    // Create model file
    FileManager.default.createFile(atPath: sut.modelFileURL.path, contents: Data("test".utf8))
    sut.checkModelStatus()
    #expect(sut.state == .ready(modelPath: sut.modelFileURL.path))

    sut.deleteModel()

    #expect(sut.state == .notDownloaded)
    #expect(!FileManager.default.fileExists(atPath: sut.modelFileURL.path))
  }

  // MARK: - Edge Cases

  @Test("checkModelStatus boundary: ~7.5 GB (8 GB device) is supported")
  func realWorld8GBDevice() {
    // iOS reports ~7.5 GB on 8 GB devices; must pass the 7 GB threshold
    let sut = makeSUT(physicalMemory: 7_500_000_000)
    sut.checkModelStatus()
    #expect(sut.state != .unsupportedDevice)
  }

  // MARK: - SHA256

  @Test("computeSHA256 returns correct hash for known data")
  func computeSHA256ReturnsCorrectHash() throws {
    let tempFile = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let data = Data(repeating: 0x42, count: 1000)
    try data.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let hash = try ModelManager.computeSHA256(of: tempFile)
    // Precomputed: SHA256 of 1000 bytes of 0x42
    #expect(hash == "9a5670771141349931d69d6eb982faa01def544dc17a161ef83b3277fb7c0c3c")
  }

  @Test("downloadModel transitions to ready when SHA256 matches")
  func downloadSuccessWithMatchingSHA256() async {
    // MockModelDownloader writes 1000 bytes of 0x42
    let expectedHash = "9a5670771141349931d69d6eb982faa01def544dc17a161ef83b3277fb7c0c3c"
    let sut = makeSUT(
      downloader: MockModelDownloader(statusCode: 200, simulateBytes: 1000),
      expectedSHA256: expectedHash
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    if case .ready = sut.state {
      // Success
    } else {
      Issue.record("Expected .ready but got \(sut.state)")
    }
  }

  @Test("downloadModel transitions to error when SHA256 mismatches")
  func downloadFailureWithMismatchingSHA256() async {
    let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
    let sut = makeSUT(
      downloader: MockModelDownloader(statusCode: 200, simulateBytes: 1000),
      expectedSHA256: wrongHash
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    if case .error(let message) = sut.state {
      #expect(message.contains("verification failed"))
    } else {
      Issue.record("Expected .error but got \(sut.state)")
    }

    // .download file should be deleted on mismatch
    #expect(!FileManager.default.fileExists(atPath: sut.downloadFileURL.path))
  }

  @Test("downloadModel skips SHA256 verification when expectedSHA256 is nil")
  func downloadSuccessWithNilSHA256() async {
    let sut = makeSUT(
      downloader: MockModelDownloader(statusCode: 200, simulateBytes: 100)
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    if case .ready = sut.state {
      // Success — no SHA256 check performed
    } else {
      Issue.record("Expected .ready but got \(sut.state)")
    }
  }
}
