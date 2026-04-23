import Foundation
import Testing

@testable import Pastura

// MARK: - Tests (joins the serialized `ModelManagerTests` suite)
//
// Sibling-file extension per .claude/rules/testing.md. A standalone `@Suite`
// would race against `ModelManagerTests` on shared filesystem paths because
// Swift Testing runs suites in parallel by default — `.serialized` only
// orders tests *within* a suite.

extension ModelManagerTests {

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
    let descriptor = makeTestDescriptor(sha256: expectedHash)
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 1000),
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    #expect(sut.activeState == .notDownloaded)

    await sut.downloadModel(descriptor: descriptor)
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
      try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
    }

    if case .ready = sut.activeState {
      // Success
    } else {
      Issue.record("Expected .ready but got \(sut.activeState)")
    }
  }

  @Test("downloadModel transitions to error when SHA256 mismatches")
  func downloadFailureWithMismatchingSHA256() async {
    let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
    let descriptor = makeTestDescriptor(sha256: wrongHash)
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 1000),
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    #expect(sut.activeState == .notDownloaded)

    await sut.downloadModel(descriptor: descriptor)
    let downloadURL = sut.downloadFileURL(for: descriptor)
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
      try? FileManager.default.removeItem(at: downloadURL)
    }

    if case .error(let message) = sut.activeState {
      #expect(message.contains("verification failed"))
    } else {
      Issue.record("Expected .error but got \(sut.activeState)")
    }

    // .download file should be deleted on mismatch
    #expect(!FileManager.default.fileExists(atPath: downloadURL.path))
  }

  @Test("downloadModel skips SHA256 verification when descriptor sha256 is empty")
  func downloadSuccessWithEmptySHA256() async {
    let descriptor = makeTestDescriptor(sha256: "")  // empty = skip
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 100),
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    #expect(sut.activeState == .notDownloaded)

    await sut.downloadModel(descriptor: descriptor)
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
      try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
    }

    if case .ready = sut.activeState {
      // Success — no SHA256 check performed
    } else {
      Issue.record("Expected .ready but got \(sut.activeState)")
    }
  }
}
