import Foundation
import Testing

@testable import Pastura

extension ModelManagerTests {
  // MARK: - cancelDownloadAndDelete(descriptor:) — destructive variant
  //
  // The destructive contract complements `cancelDownload(descriptor:)`'s
  // resume-friendly behavior. These tests pin the side effects (state +
  // both files removed) so a future "simplification" cannot silently
  // demote it back to the non-destructive variant.

  @Test("cancelDownloadAndDelete removes both partial and model files")
  func cancelDownloadAndDelete_removesAllFiles() async throws {
    let descriptor = makeTestDescriptor(
      id: "destructive-target", fileName: "destructive-target.gguf")
    let sut = makeSUT(catalog: [descriptor])

    let modelURL = sut.modelFileURL(for: descriptor)
    let partialURL = sut.downloadFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelURL.path, contents: Data("model".utf8))
    FileManager.default.createFile(atPath: partialURL.path, contents: Data("partial".utf8))
    defer {
      try? FileManager.default.removeItem(at: modelURL)
      try? FileManager.default.removeItem(at: partialURL)
    }

    await sut.cancelDownloadAndDelete(descriptor: descriptor)

    #expect(sut.state[descriptor.id] == .notDownloaded)
    #expect(
      !FileManager.default.fileExists(atPath: modelURL.path),
      "Model file must be removed by destructive cancel")
    #expect(
      !FileManager.default.fileExists(atPath: partialURL.path),
      "Partial download file must be removed by destructive cancel")
  }

  @Test("cancelDownloadAndDelete is idempotent when no files exist")
  func cancelDownloadAndDelete_idempotent() async {
    let descriptor = makeTestDescriptor(
      id: "idempotent-target", fileName: "idempotent-target.gguf")
    let sut = makeSUT(catalog: [descriptor])
    sut.checkModelStatus()
    #expect(sut.state[descriptor.id] == .notDownloaded)

    await sut.cancelDownloadAndDelete(descriptor: descriptor)

    #expect(sut.state[descriptor.id] == .notDownloaded)
  }

  @Test("cancelDownloadAndDelete clears a .ready state and removes its file")
  func cancelDownloadAndDelete_ready_clears() async throws {
    let descriptor = makeTestDescriptor(
      id: "ready-target", fileName: "ready-target.gguf")
    let sut = makeSUT(catalog: [descriptor])

    let modelURL = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelURL.path, contents: Data("ready".utf8))
    defer { try? FileManager.default.removeItem(at: modelURL) }
    sut.checkModelStatus()
    guard case .ready = sut.state[descriptor.id] else {
      Issue.record("Setup failed: expected .ready")
      return
    }

    await sut.cancelDownloadAndDelete(descriptor: descriptor)

    #expect(sut.state[descriptor.id] == .notDownloaded)
    #expect(!FileManager.default.fileExists(atPath: modelURL.path))
  }
}
