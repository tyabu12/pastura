import Foundation
import Testing

@testable import Pastura

// MARK: - Tests (joins the serialized `ModelManagerTests` suite)
//
// Multi-descriptor specific coverage: state seeding, shared RAM floor across
// descriptors, Gemma legacy filename compat, sequential download policy,
// active-model persistence, and `resolveInitialActiveID` resolution logic.

extension ModelManagerTests {

  // MARK: - State Seeding

  @Test("state dict seeds an entry for every catalog descriptor at init")
  func stateSeedsAllCatalogDescriptors() {
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(catalog: [first, second])
    #expect(sut.state["a"] == .checking)
    #expect(sut.state["b"] == .checking)
    #expect(sut.state.count == 2)
  }

  @Test("unsupportedDevice state applies to every catalog descriptor")
  func unsupportedDeviceAppliesToAllCatalogDescriptors() {
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(physicalMemory: 5_500_000_000, catalog: [first, second])
    sut.checkModelStatus()
    #expect(sut.state["a"] == .unsupportedDevice)
    #expect(sut.state["b"] == .unsupportedDevice)
  }

  // MARK: - Gemma Legacy Compat
  //
  // Upgrade contract: existing TestFlight users have a fully-downloaded
  // Gemma 4 E2B (Q4_K_M) at `Application Support/gemma-4-E2B-it-Q4_K_M.gguf`
  // (and possibly a partial `.download` in Caches/). The multi-model refactor
  // must NOT force these users to re-download 3.1 GB.

  @Test("Gemma legacy fileName resolves to Application Support path")
  func gemmaLegacyModelFileURLPath() {
    let descriptor = makeTestDescriptor(fileName: "gemma-4-E2B-it-Q4_K_M.gguf")
    let sut = makeSUT(catalog: [descriptor])
    let modelURL = sut.modelFileURL(for: descriptor)
    #expect(modelURL.lastPathComponent == "gemma-4-E2B-it-Q4_K_M.gguf")
    #expect(modelURL.path.contains("Application Support"))
  }

  @Test("Gemma legacy partial filename resolves to Caches/<name>.download")
  func gemmaLegacyDownloadFileURLPath() {
    let descriptor = makeTestDescriptor(fileName: "gemma-4-E2B-it-Q4_K_M.gguf")
    let sut = makeSUT(catalog: [descriptor])
    let downloadURL = sut.downloadFileURL(for: descriptor)
    #expect(downloadURL.lastPathComponent == "gemma-4-E2B-it-Q4_K_M.gguf.download")
    #expect(downloadURL.path.contains("Caches"))
  }

  @Test("Gemma legacy completed file is auto-recognized as .ready without re-download")
  func gemmaLegacyCompletedFileAutoRecognized() throws {
    let descriptor = makeTestDescriptor(
      fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
      fileSize: 100
    )
    let sut = makeSUT(catalog: [descriptor])

    // Pre-populate a file matching the exact legacy filename and size
    let modelURL = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x42, count: 100).write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: modelURL) }

    sut.checkModelStatus()

    // State resolves to .ready WITHOUT invoking a download. This is the
    // load-bearing assertion — if this ever regresses, every existing
    // TestFlight user faces a 3.1 GB re-download on upgrade.
    #expect(sut.state[descriptor.id] == .ready(modelPath: modelURL.path))
  }

  @Test("Gemma legacy completed file with size mismatch is removed (not re-blessed)")
  func gemmaLegacyCompletedFileWithWrongSizeIsRejected() throws {
    let descriptor = makeTestDescriptor(
      fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
      fileSize: 100
    )
    let sut = makeSUT(catalog: [descriptor])

    // Place a file of the wrong size — simulates a corrupted / truncated legacy file
    let modelURL = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x42, count: 42).write(to: modelURL)

    sut.checkModelStatus()

    #expect(sut.state[descriptor.id] == .notDownloaded)
    #expect(!FileManager.default.fileExists(atPath: modelURL.path))
  }

  // MARK: - Sequential Download Policy

  @Test("startDownload is rejected when another descriptor is already downloading")
  func sequentialDownloadPolicyRejectsSecondStart() async {
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(catalog: [first, second])
    defer {
      sut.cancelDownload(descriptor: first)
      for descriptor in [first, second] {
        try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
        try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
      }
    }

    sut.checkModelStatus()
    #expect(sut.state["a"] == .notDownloaded)
    #expect(sut.state["b"] == .notDownloaded)

    // Start A — synchronously transitions to .downloading BEFORE the Task runs
    sut.startDownload(descriptor: first)
    #expect(sut.isAnyDownloadInProgress)

    // Attempt B — must be rejected (policy guard), state stays .notDownloaded
    let bStateBefore = sut.state["b"]
    sut.startDownload(descriptor: second)
    #expect(sut.state["b"] == bStateBefore)
  }

  // MARK: - setActiveModel

  @Test("setActiveModel accepts known id and persists to UserDefaults")
  func setActiveModelPersistsKnownID() {
    let defaults = Self.isolatedUserDefaults()
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(catalog: [first, second], userDefaults: defaults)

    sut.setActiveModel("b")
    #expect(sut.activeModelID == "b")
    #expect(defaults.string(forKey: ModelManager.activeModelIDKey) == "b")
  }

  @Test("setActiveModel ignores unknown id (activeModelID unchanged)")
  func setActiveModelIgnoresUnknownID() {
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(catalog: [first, second])
    let initialActive = sut.activeModelID

    sut.setActiveModel("non-existent")
    #expect(sut.activeModelID == initialActive)
  }

  @Test("init resumes persisted activeModelID when it maps to the catalog")
  func initResumesPersistedActiveID() {
    let defaults = Self.isolatedUserDefaults()
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    defaults.set("b", forKey: ModelManager.activeModelIDKey)

    let sut = makeSUT(catalog: [first, second], userDefaults: defaults)
    #expect(sut.activeModelID == "b")
  }

  // MARK: - resolveInitialActiveID (static)

  @Test("resolveInitialActiveID returns persisted id when present in catalog")
  func resolveInitialActiveID_prefersPersistedValid() {
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let id = ModelManager.resolveInitialActiveID(persistedID: "b", catalog: [first, second])
    #expect(id == "b")
  }

  @Test("resolveInitialActiveID falls back to defaultInitialModelID when persisted is unknown")
  func resolveInitialActiveID_fallsBackToDefault() {
    let id = ModelManager.resolveInitialActiveID(
      persistedID: "unknown",
      catalog: ModelRegistry.catalog
    )
    #expect(id == ModelRegistry.defaultInitialModelID)
  }

  @Test("resolveInitialActiveID falls back to catalog.first when default is not in catalog")
  func resolveInitialActiveID_fallsBackToFirstWhenDefaultAbsent() {
    let first = makeTestDescriptor(id: "test-x", fileName: "test-x.gguf")
    let second = makeTestDescriptor(id: "test-y", fileName: "test-y.gguf")
    let id = ModelManager.resolveInitialActiveID(persistedID: nil, catalog: [first, second])
    #expect(id == "test-x")
  }

  @Test("resolveInitialActiveID returns empty string for empty catalog")
  func resolveInitialActiveID_emptyCatalogReturnsEmpty() {
    let id = ModelManager.resolveInitialActiveID(persistedID: "anything", catalog: [])
    #expect(id == "")
  }
}
