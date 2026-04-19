import CryptoKit
import Foundation
import Testing

@testable import Pastura

// MARK: - Mock

/// A test double for `ModelDownloader` that returns immediately or throws.
struct MockModelDownloader: ModelDownloader, Sendable {
  let result: @Sendable () throws -> Void
  let simulateBytes: Int64

  init(simulateBytes: Int64 = 1000) {
    self.result = {}
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
  ) async throws {
    try result()
    // Write dummy bytes to the destination to simulate a completed download
    let data = Data(repeating: 0x42, count: Int(simulateBytes))
    try data.write(to: destination)
    progressHandler(simulateBytes, simulateBytes)
  }
}

/// Mock that emits ONLY sub-1.0 progress callbacks and never a terminal
/// `received == total` callback. Mirrors production `URLSessionDownloadDelegate`
/// behavior: `didWriteData` is not guaranteed to fire one final time at 100%
/// after the last chunk — completion arrives via `didCompleteWithError(nil)`.
struct SubOneProgressMockDownloader: ModelDownloader, Sendable {
  let simulateBytes: Int64

  init(simulateBytes: Int64 = 1000) {
    self.simulateBytes = simulateBytes
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws {
    let data = Data(repeating: 0x42, count: Int(simulateBytes))
    try data.write(to: destination)
    // Emit only a mid-progress callback — never terminal 100%.
    progressHandler(simulateBytes / 2, simulateBytes)
  }
}

// MARK: - Tests

// Download tests share filesystem paths (Documents directory), so serialize to avoid races.
@Suite("ModelManager", .serialized, .timeLimit(.minutes(1)))
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
  func modelReady() throws {
    let sut = makeSUT()

    // Place a dummy file at the model path
    let modelPath = sut.modelFileURL
    try FileManager.default.createDirectory(
      at: modelPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelPath.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: modelPath) }

    sut.checkModelStatus()
    #expect(sut.state == .ready(modelPath: modelPath.path))
  }

  // MARK: - Download

  @Test("downloadModel transitions from notDownloaded to ready on success")
  func downloadSuccess() async {
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 100)
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
  func deleteModel() throws {
    let sut = makeSUT()

    // Create model file
    try FileManager.default.createDirectory(
      at: sut.modelFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: sut.modelFileURL.path, contents: Data("test".utf8))
    sut.checkModelStatus()
    #expect(sut.state == .ready(modelPath: sut.modelFileURL.path))

    sut.deleteModel()

    #expect(sut.state == .notDownloaded)
    #expect(!FileManager.default.fileExists(atPath: sut.modelFileURL.path))
  }

  // MARK: - Storage Location

  @Test("modelFileURL is in Application Support directory")
  func modelFileInApplicationSupport() {
    let sut = makeSUT()
    #expect(sut.modelFileURL.path.contains("Application Support"))
    #expect(!sut.modelFileURL.path.contains("Documents"))
  }

  @Test("downloadFileURL is in Caches directory")
  func downloadFileInCaches() {
    let sut = makeSUT()
    #expect(sut.downloadFileURL.path.contains("Caches"))
    #expect(!sut.downloadFileURL.path.contains("Documents"))
  }

  // MARK: - iCloud Backup Exclusion

  @Test("checkModelStatus sets isExcludedFromBackup on existing model file")
  func checkModelStatusExcludesFromBackup() throws {
    let sut = makeSUT()

    // Create the model directory and file
    let modelDir = sut.modelFileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: sut.modelFileURL.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: sut.modelFileURL) }

    sut.checkModelStatus()

    let values = try sut.modelFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test("downloadModel sets isExcludedFromBackup on completed model file")
  func downloadSetsExcludeFromBackup() async throws {
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 100)
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    guard case .ready = sut.state else {
      Issue.record("Expected .ready but got \(sut.state)")
      return
    }

    let values = try sut.modelFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
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
      downloader: MockModelDownloader(simulateBytes: 1000),
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
      downloader: MockModelDownloader(simulateBytes: 1000),
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
      downloader: MockModelDownloader(simulateBytes: 100)
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

  // MARK: - Terminal Progress

  @Test(
    "downloadModel transitions to ready and reaches 100% even when downloader skips terminal callback"
  )
  func downloadCompletesWhenDownloaderSkipsTerminalProgress() async {
    // Production URLSession does not guarantee a terminal `didWriteData` call;
    // ModelManager must explicitly bring `state` to 1.0 before SHA256 verification
    // so the user sees 100% rather than stalling at the last sub-1.0 sample
    // during the ~2s SHA256 hash on a 3 GB file.
    let sut = makeSUT(
      downloader: SubOneProgressMockDownloader(simulateBytes: 1000),
      // Use SHA256 verification to exercise the post-download path that
      // includes the explicit `state = .downloading(progress: 1.0)` transition.
      expectedSHA256: "9a5670771141349931d69d6eb982faa01def544dc17a161ef83b3277fb7c0c3c"
    )
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    // Snapshot state changes via re-arming Observation tracking.
    let snapshots = StateSnapshots()
    snapshots.startObserving(sut)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    // Drain any pending observer Tasks so the final transitions are recorded.
    for _ in 0..<5 { await Task.yield() }

    guard case .ready = sut.state else {
      Issue.record("Expected .ready but got \(sut.state)")
      return
    }

    let progresses = snapshots.progresses
    #expect(
      progresses.contains(where: { $0 >= 0.999 }),
      "Expected progress to reach 1.0 before .ready; observed \(progresses)"
    )
  }
}

/// Re-arming `withObservationTracking` collector for `ModelManager.state`.
/// Each fired change records the current progress value (if any) and re-arms
/// tracking for the next change. Lives on MainActor because it reads/writes
/// `ModelManager.state`.
@MainActor
private final class StateSnapshots {
  private(set) var progresses: [Double] = []

  func startObserving(_ manager: ModelManager) {
    record(manager.state)
    withObservationTracking {
      _ = manager.state
    } onChange: { [weak self, weak manager] in
      // onChange fires synchronously on the mutating actor; re-arm via a Task
      // so the next mutation is captured.
      Task { @MainActor [weak self, weak manager] in
        guard let self, let manager else { return }
        self.startObserving(manager)
      }
    }
  }

  private func record(_ state: ModelState) {
    if case .downloading(let progress) = state {
      progresses.append(progress)
    }
  }
}
