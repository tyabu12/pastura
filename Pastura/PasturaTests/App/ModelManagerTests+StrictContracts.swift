import Foundation
import Testing

@testable import Pastura

// MARK: - Tests (joins the serialized `ModelManagerTests` suite)
//
// PR B (#210) strict-contract coverage split out of
// `ModelManagerTests+MultiModel.swift` to keep that file under the
// 400-line `file_length` budget. Focused on surfaces that UI gates on:
//
// - `deleteModel(id:)` — throwing guard contract
// - `shouldShowInitialModelPicker` — fresh-install gate
// - `cancelDownload(descriptor:)` — idempotency on non-`.downloading`
//   states

extension ModelManagerTests {

  // MARK: - deleteModel(id:) — strict-guard contract

  @Test("deleteModel succeeds for a .ready non-active model, removing file + state")
  func deleteModel_readyNonActive_succeeds() throws {
    let active = makeTestDescriptor(id: "active-a", fileName: "active-a.gguf")
    let other = makeTestDescriptor(id: "other-b", fileName: "other-b.gguf")
    let sut = makeSUT(catalog: [active, other])
    #expect(sut.activeModelID == "active-a")

    let otherURL = sut.modelFileURL(for: other)
    try FileManager.default.createDirectory(
      at: otherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: otherURL.path, contents: Data("test".utf8))
    sut.checkModelStatus()
    guard case .ready = sut.state["other-b"] else {
      Issue.record("Setup failed: expected .ready for non-active descriptor")
      return
    }

    try sut.deleteModel(id: "other-b")

    #expect(sut.state["other-b"] == .notDownloaded)
    #expect(!FileManager.default.fileExists(atPath: otherURL.path))
    defer { try? FileManager.default.removeItem(at: otherURL) }
  }

  @Test("deleteModel rejects active model with .cannotDeleteActive")
  func deleteModel_active_rejects() throws {
    let active = makeTestDescriptor(id: "active-a", fileName: "active-a.gguf")
    let other = makeTestDescriptor(id: "other-b", fileName: "other-b.gguf")
    let sut = makeSUT(catalog: [active, other])

    let activeURL = sut.modelFileURL(for: active)
    try FileManager.default.createDirectory(
      at: activeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: activeURL.path, contents: Data("test".utf8))
    sut.checkModelStatus()
    defer { try? FileManager.default.removeItem(at: activeURL) }

    #expect {
      try sut.deleteModel(id: "active-a")
    } throws: { error in
      error as? ModelManagerError == .cannotDeleteActive(id: "active-a")
    }
    #expect(
      FileManager.default.fileExists(atPath: activeURL.path),
      "file must survive rejected delete")
  }

  @Test("deleteModel rejects .downloading with .notReadyForDelete (use cancelDownload)")
  func deleteModel_downloading_rejects() {
    let active = makeTestDescriptor(id: "active-a", fileName: "active-a.gguf")
    let other = makeTestDescriptor(
      id: "other-b", fileName: "other-b.gguf", fileSize: 1_000, sha256: "dummy")
    let sut = makeSUT(catalog: [active, other])
    defer {
      sut.cancelDownload(descriptor: other)
      for descriptor in [active, other] {
        try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
        try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
      }
    }

    // `startDownload` gates on the post-`checkModelStatus` resolved state
    // (`.notDownloaded`, not the init-time `.checking`). See
    // `sequentialDownloadPolicyRejectsSecondStart` for the same sequencing.
    sut.checkModelStatus()
    sut.startDownload(descriptor: other)
    guard case .downloading = sut.state["other-b"] else {
      Issue.record("Setup failed: expected .downloading")
      return
    }

    #expect {
      try sut.deleteModel(id: "other-b")
    } throws: { error in
      error as? ModelManagerError == .notReadyForDelete(id: "other-b")
    }
  }

  @Test("deleteModel on non-active succeeds during a running simulation")
  func deleteModel_nonActive_duringSimulation_succeeds() throws {
    // Pin the decoupling invariant: `ModelManager.deleteModel` must not
    // reach into `SimulationViewModel` / `SimulationActivityRegistry`.
    // Deleting a non-active model is always safe — the active file is
    // protected by the `.cannotDeleteActive` guard, and every other
    // descriptor is orthogonal to the in-flight inference.
    let registry = SimulationActivityRegistry()
    registry.enter()
    defer { registry.leave() }
    #expect(registry.isActive, "simulating a running simulation")

    let active = makeTestDescriptor(id: "active-a", fileName: "active-a.gguf")
    let other = makeTestDescriptor(id: "other-b", fileName: "other-b.gguf")
    let sut = makeSUT(catalog: [active, other])
    let otherURL = sut.modelFileURL(for: other)
    try FileManager.default.createDirectory(
      at: otherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: otherURL.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: otherURL) }
    sut.checkModelStatus()

    try sut.deleteModel(id: "other-b")

    #expect(sut.state["other-b"] == .notDownloaded)
    #expect(registry.isActive, "delete must not disturb registry state")
  }

  @Test("deleteModel rejects unknown id with .unknownModel")
  func deleteModel_unknownID_rejects() {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])

    #expect {
      try sut.deleteModel(id: "does-not-exist")
    } throws: { error in
      error as? ModelManagerError == .unknownModel(id: "does-not-exist")
    }
  }

  // MARK: - shouldShowInitialModelPicker — fresh-install gate
  //
  // Pins the three-condition contract so a future refactor can't silently
  // flip legacy Gemma users into a picker on upgrade, or show a picker
  // to unsupported-device users who would just bounce off the unsupported UI.

  @Test("fresh install on supported multi-model device → picker")
  func shouldShowInitialModelPicker_freshInstall_true() {
    let gemma = makeTestDescriptor(id: "gemma", fileName: "gemma.gguf")
    let qwen = makeTestDescriptor(id: "qwen", fileName: "qwen.gguf")
    let defaults = Self.isolatedUserDefaults()  // empty — no persisted active
    let sut = makeSUT(
      physicalMemory: 8 * 1024 * 1024 * 1024,
      catalog: [gemma, qwen],
      userDefaults: defaults)
    sut.checkModelStatus()

    #expect(sut.state["gemma"] == .notDownloaded)
    #expect(sut.state["qwen"] == .notDownloaded)
    #expect(sut.shouldShowInitialModelPicker == true)
  }

  @Test("legacy Gemma user (one file on disk) bypasses picker")
  func shouldShowInitialModelPicker_legacyGemma_false() throws {
    let gemma = makeTestDescriptor(id: "gemma", fileName: "gemma.gguf")
    let qwen = makeTestDescriptor(id: "qwen", fileName: "qwen.gguf")
    let defaults = Self.isolatedUserDefaults()  // empty — classic TestFlight upgrade
    let sut = makeSUT(
      physicalMemory: 8 * 1024 * 1024 * 1024,
      catalog: [gemma, qwen],
      userDefaults: defaults)
    let gemmaURL = sut.modelFileURL(for: gemma)
    try FileManager.default.createDirectory(
      at: gemmaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: gemmaURL.path, contents: Data("existing".utf8))
    defer { try? FileManager.default.removeItem(at: gemmaURL) }
    sut.checkModelStatus()

    guard case .ready = sut.state["gemma"] else {
      Issue.record("Setup failed: expected .ready for legacy Gemma")
      return
    }
    #expect(sut.shouldShowInitialModelPicker == false)
  }

  @Test("fresh install on unsupported device → falls through to .needsModelDownload flow")
  func shouldShowInitialModelPicker_unsupportedDevice_false() {
    let gemma = makeTestDescriptor(id: "gemma", fileName: "gemma.gguf")
    let qwen = makeTestDescriptor(id: "qwen", fileName: "qwen.gguf")
    let defaults = Self.isolatedUserDefaults()
    let sut = makeSUT(
      physicalMemory: 5_500_000_000,  // below shared 6.5 GB floor
      catalog: [gemma, qwen],
      userDefaults: defaults)
    sut.checkModelStatus()

    #expect(sut.state["gemma"] == .unsupportedDevice)
    #expect(sut.state["qwen"] == .unsupportedDevice)
    #expect(
      sut.shouldShowInitialModelPicker == false,
      "unsupported device must not see picker — existing needsModelDownload UI handles it")
  }

  @Test("returning user with persisted id bypasses picker even on fresh install")
  func shouldShowInitialModelPicker_persistedID_false() {
    let gemma = makeTestDescriptor(id: "gemma", fileName: "gemma.gguf")
    let qwen = makeTestDescriptor(id: "qwen", fileName: "qwen.gguf")
    let defaults = Self.isolatedUserDefaults()
    defaults.set("gemma", forKey: ModelManager.activeModelIDKey)
    let sut = makeSUT(
      physicalMemory: 8 * 1024 * 1024 * 1024,
      catalog: [gemma, qwen],
      userDefaults: defaults)
    sut.checkModelStatus()

    #expect(sut.hadPersistedActiveIDAtInit == true)
    #expect(sut.shouldShowInitialModelPicker == false)
  }

  @Test("single-model catalog never shows picker")
  func shouldShowInitialModelPicker_singleModelCatalog_false() {
    let only = makeTestDescriptor(id: "only", fileName: "only.gguf")
    let defaults = Self.isolatedUserDefaults()
    let sut = makeSUT(
      physicalMemory: 8 * 1024 * 1024 * 1024,
      catalog: [only],
      userDefaults: defaults)
    sut.checkModelStatus()

    #expect(sut.shouldShowInitialModelPicker == false)
  }

  // MARK: - cancelDownload(descriptor:) — idempotency contract
  //
  // The docstring pins the "non-`.downloading` states are preserved" invariant;
  // these tests prevent silent drift if someone later simplifies cancelDownload
  // to unconditionally set `.notDownloaded`.

  @Test("cancelDownload on .ready is a no-op (preserves state)")
  func cancelDownload_ready_noop() throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])

    let modelURL = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelURL.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: modelURL) }
    sut.checkModelStatus()
    let beforeState = sut.state[descriptor.id]
    guard case .ready = beforeState else {
      Issue.record("Setup failed: expected .ready")
      return
    }

    sut.cancelDownload(descriptor: descriptor)

    #expect(sut.state[descriptor.id] == beforeState, ".ready must survive cancelDownload")
  }

  @Test("cancelDownload on .error is a no-op (preserves state)")
  func cancelDownload_error_noop() async {
    let descriptor = makeTestDescriptor(
      id: "error-target", fileName: "error-target.gguf",
      fileSize: 1_000, sha256: "required-but-will-mismatch")
    // Downloader that writes bytes but with a SHA256 mismatch → finalizeDownload
    // flips state to `.error` via the existing integrity path.
    let sut = makeSUT(
      downloader: MockModelDownloader(simulateBytes: 1_000),
      catalog: [descriptor])
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
      try? FileManager.default.removeItem(at: sut.downloadFileURL(for: descriptor))
    }

    sut.checkModelStatus()
    await sut.downloadModel(descriptor: descriptor)
    guard case .error = sut.state[descriptor.id] else {
      Issue.record("Setup failed: expected .error after SHA mismatch")
      return
    }
    let beforeState = sut.state[descriptor.id]

    sut.cancelDownload(descriptor: descriptor)

    #expect(sut.state[descriptor.id] == beforeState, ".error must survive cancelDownload")
  }

  @Test("cancelDownload on .notDownloaded is a no-op (preserves state)")
  func cancelDownload_notDownloaded_noop() {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])
    sut.checkModelStatus()
    #expect(sut.state[descriptor.id] == .notDownloaded)

    sut.cancelDownload(descriptor: descriptor)

    #expect(sut.state[descriptor.id] == .notDownloaded, ".notDownloaded idempotent")
  }
}
