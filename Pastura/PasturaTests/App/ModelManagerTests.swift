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

// MARK: - Tests

// Download tests share filesystem paths (Documents directory), so serialize to avoid races.
@Suite("ModelManager", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ModelManagerTests {

  // MARK: - SUT Helpers
  //
  // Helpers are `internal` (not `private`) so sibling-file extensions
  // (`ModelManagerTests+ProgressRegression.swift`, `ModelManagerTests+MultiModel.swift`)
  // can call them. Per .claude/rules/testing.md — widening to module-internal
  // is contained because the test target is its own module.

  /// Default filename for the test Gemma descriptor. Matches the legacy constant
  /// `gemma-4-E2B-it-Q4_K_M.gguf` to exercise upgrade-compat paths on the
  /// standard test SUT.
  static let testGemmaFileName = "gemma-4-E2B-it-Q4_K_M.gguf"

  /// Convenience factory for a minimal `ModelDescriptor` suitable for most
  /// tests. `fileSize: 0` / `sha256: ""` skip size / SHA validation — pass
  /// explicit values to exercise the validation paths.
  func makeTestDescriptor(
    id: ModelID = "test-gemma",
    fileName: String = testGemmaFileName,
    fileSize: Int64 = 0,
    sha256: String = "",
    systemPromptSuffix: String? = nil
  ) -> ModelDescriptor {
    ModelDescriptor(
      id: id,
      displayName: "Test Model",
      vendor: "Test Vendor",
      vendorURL: URL(string: "https://example.com")!,
      downloadURL: URL(string: "https://example.com/\(fileName)")!,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256,
      stopSequence: "<|im_end|>",
      minRAM: 6_500_000_000,
      modelInfoURL: URL(string: "https://example.com")!,
      systemPromptSuffix: systemPromptSuffix
    )
  }

  /// Builds a per-test isolated `UserDefaults` instance. The returned suite
  /// writes to disk but uses a unique name so no test leaks state to another.
  static func isolatedUserDefaults() -> UserDefaults {
    let name = "ModelManagerTests-\(UUID().uuidString)"
    // Safe: `UserDefaults(suiteName:)` only returns nil for reserved names
    // ("NSGlobalDomain", "NSRegistrationDomain"); a UUID-based name never collides.
    return UserDefaults(suiteName: name) ?? .standard
  }

  func makeSUT(
    downloader: any ModelDownloader = MockModelDownloader(),
    physicalMemory: UInt64 = 8 * 1024 * 1024 * 1024,
    catalog: [ModelDescriptor]? = nil,
    userDefaults: UserDefaults? = nil,
    networkPathMonitor: (any NetworkPathMonitoring)? = nil,
    consentStore: (any CellularConsentStoring)? = nil
  ) -> ModelManager {
    let finalCatalog = catalog ?? [makeTestDescriptor()]
    let finalDefaults = userDefaults ?? Self.isolatedUserDefaults()
    // Default to mocks so tests don't accidentally pick up real cellular
    // state from the host's `NWPathMonitor`. Tests that exercise the
    // cellular gate (`#191`) inject explicit mocks; everyone else gets
    // a Wi-Fi-equivalent stub.
    let finalMonitor = networkPathMonitor ?? MockNetworkPathMonitor(isCellular: false)
    let finalConsent = consentStore ?? MockCellularConsentStore(hasCellularConsent: false)
    let sut = ModelManager(
      downloader: downloader,
      fileManager: .default,
      physicalMemory: physicalMemory,
      userDefaults: finalDefaults,
      catalog: finalCatalog,
      networkPathMonitor: finalMonitor,
      consentStore: finalConsent
    )
    // Proactively wipe residual files at the shared Application Support /
    // Caches paths. Each per-test `defer { removeItem }` is declared AFTER
    // `await sut.downloadModel(...)` — if a download-triggering test crashes
    // before its defer registers, the model file leaks and every subsequent
    // `.notDownloaded` assertion in the suite fails spuriously. The upstream
    // cleanup here breaks that cascade so the actual failing test surfaces
    // cleanly. Per-test defers are kept as defense-in-depth for the same-test
    // window and are intentional — do not remove them as "redundant".
    //
    // First observed on CI post-#186 (sha e650f13) on the macos-26 runner.
    for descriptor in finalCatalog {
      try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
      try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
      // Loud guard: surface permission / sandbox oddities that `try?` would
      // otherwise swallow.
      #expect(!FileManager.default.fileExists(atPath: sut.modelFileURL(for: descriptor).path))
      #expect(!FileManager.default.fileExists(atPath: sut.downloadFileURL(for: descriptor).path))
    }
    return sut
  }

  // MARK: - Device Check

  @Test("checkModelStatus sets unsupportedDevice when RAM < 6.5 GB threshold")
  func unsupportedDevice() {
    // 5.5 GB simulates what iOS reports on a 6 GB device
    let sut = makeSUT(physicalMemory: 5_500_000_000)
    sut.checkModelStatus()
    #expect(sut.activeState == .unsupportedDevice)
  }

  @Test("checkModelStatus sets notDownloaded when model file does not exist")
  func modelNotDownloaded() {
    let sut = makeSUT()
    sut.checkModelStatus()
    #expect(sut.activeState == .notDownloaded)
  }

  @Test("checkModelStatus sets ready when model file exists")
  func modelReady() throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])

    // Place a dummy file at the model path
    let modelPath = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelPath.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: modelPath) }

    sut.checkModelStatus()
    #expect(sut.activeState == .ready(modelPath: modelPath.path))
  }

  // MARK: - Download

  @Test("downloadModel transitions from notDownloaded to ready on success")
  func downloadSuccess() async {
    let descriptor = makeTestDescriptor()
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
      // Success
    } else {
      Issue.record("Expected .ready but got \(sut.activeState)")
    }
  }

  @Test("downloadModel transitions to error on download failure")
  func downloadFailure() async {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      downloader: MockModelDownloader(error: URLError(.notConnectedToInternet)),
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    #expect(sut.activeState == .notDownloaded)

    await sut.downloadModel(descriptor: descriptor)

    if case .error = sut.activeState {
      // Expected
    } else {
      Issue.record("Expected .error but got \(sut.activeState)")
    }
  }

  @Test("downloadModel is no-op when state is unsupportedDevice")
  func downloadNoOpWhenUnsupported() async {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      physicalMemory: 4 * 1024 * 1024 * 1024,
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    #expect(sut.activeState == .unsupportedDevice)

    await sut.downloadModel(descriptor: descriptor)
    #expect(sut.activeState == .unsupportedDevice)
  }

  @Test("downloadModel retries from error state")
  func downloadRetryFromError() async {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      downloader: MockModelDownloader(error: URLError(.timedOut)),
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    await sut.downloadModel(descriptor: descriptor)

    guard case .error = sut.activeState else {
      Issue.record("Expected .error after first download attempt")
      return
    }

    // Second call also fails (same downloader), but verifies it proceeds from .error
    await sut.downloadModel(descriptor: descriptor)
    if case .error = sut.activeState {
      // Expected
    } else {
      Issue.record("Expected .error on retry with failing downloader")
    }
  }

  // MARK: - Delete
  //
  // Delete tests live in `ModelManagerTests+MultiModel.swift` because the
  // strict `deleteModel(id:)` guard requires a 2+ descriptor catalog to
  // exercise the "delete non-active" happy path without hitting the
  // `.cannotDeleteActive` reject.

  // MARK: - Storage Location

  @Test("modelFileURL is in Application Support directory")
  func modelFileInApplicationSupport() {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])
    let modelURL = sut.modelFileURL(for: descriptor)
    #expect(modelURL.path.contains("Application Support"))
    #expect(!modelURL.path.contains("Documents"))
  }

  @Test("downloadFileURL is in Caches directory")
  func downloadFileInCaches() {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])
    let downloadURL = sut.downloadFileURL(for: descriptor)
    #expect(downloadURL.path.contains("Caches"))
    #expect(!downloadURL.path.contains("Documents"))
  }

  // MARK: - iCloud Backup Exclusion

  @Test("checkModelStatus sets isExcludedFromBackup on existing model file")
  func checkModelStatusExcludesFromBackup() throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])

    // Create the model directory and file
    let modelURL = sut.modelFileURL(for: descriptor)
    let modelDir = modelURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelURL.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: modelURL) }

    sut.checkModelStatus()

    let values = try modelURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test("downloadModel sets isExcludedFromBackup on completed model file")
  func downloadSetsExcludeFromBackup() async throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 100),
      catalog: [descriptor]
    )
    sut.checkModelStatus()
    #expect(sut.activeState == .notDownloaded)

    await sut.downloadModel(descriptor: descriptor)
    let modelURL = sut.modelFileURL(for: descriptor)
    defer {
      try? FileManager.default.removeItem(at: modelURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
    }

    guard case .ready = sut.activeState else {
      Issue.record("Expected .ready but got \(sut.activeState)")
      return
    }

    let values = try modelURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  // MARK: - Edge Cases

  @Test("checkModelStatus boundary: ~7.5 GB (8 GB device) is supported")
  func realWorld8GBDevice() {
    // iOS reports ~7.5 GB on 8 GB devices; must pass the 6.5 GB threshold
    let sut = makeSUT(physicalMemory: 7_500_000_000)
    sut.checkModelStatus()
    #expect(sut.activeState != .unsupportedDevice)
  }

}
