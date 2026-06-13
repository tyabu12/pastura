import Foundation
import Testing

@testable import Pastura

// MARK: - Orphaned-model-file API
//
// Sibling-file extension of the `ModelManager` suite — NOT a new `@Suite`
// (see `.claude/rules/testing.md` § "Splitting a Suite Across Files"; a
// separate suite would race against the shared Application Support / Caches
// paths these tests write to). Assertions are membership-based (the planted
// unique-named file appears / a catalog file does not), never global counts,
// so a stray `.gguf` left by a crashed prior run cannot flip the result.
// Every planted file is removed via `defer` even on assertion failure.
extension ModelManagerTests {

  /// Plants a uniquely-named `.gguf` (no catalog entry) in the model
  /// directory and asserts `orphanedModelFiles()` surfaces it with the
  /// correct on-disk size.
  @Test func orphanedModelFiles_detectsNonCatalogGGUFWithSize() throws {
    let sut = makeSUT(catalog: [makeTestDescriptor()])
    try FileManager.default.createDirectory(
      at: sut.modelDirectoryURL, withIntermediateDirectories: true)
    let orphanName = "superseded-\(UUID().uuidString).gguf"
    let orphanURL = sut.modelDirectoryURL.appendingPathComponent(orphanName)
    let payload = Data(repeating: 0x42, count: 256)
    try payload.write(to: orphanURL)
    defer { try? FileManager.default.removeItem(at: orphanURL) }

    let orphans = sut.orphanedModelFiles()
    let match = orphans.first { $0.fileName == orphanName }
    #expect(match != nil)
    #expect(match?.sizeBytes == 256)
  }

  /// A file whose name matches a catalog `fileName` is NOT an orphan — it
  /// is a (possibly active) catalog model, surfaced through the normal
  /// per-model row instead. Exclusion is keyed purely off catalog
  /// membership, NOT `ModelState`: `checkModelStatus()` is deliberately not
  /// called, so the descriptor sits in its initial `.checking` (non-`.ready`)
  /// state — proving an in-flight finalize (catalog file on disk while the
  /// descriptor is still downloading) cannot be mislabeled an orphan.
  @Test func orphanedModelFiles_excludesCatalogFileName() throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])
    let modelURL = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x42, count: 64).write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: modelURL) }

    #expect(sut.activeState == .checking)  // non-`.ready`: exclusion is state-independent
    let orphans = sut.orphanedModelFiles()
    #expect(!orphans.contains { $0.fileName == descriptor.fileName })
  }

  /// A partial download (`<fileName>.download` in Caches) is never reported
  /// as an orphan — it lives in a different directory and carries a
  /// non-`.gguf` extension. Regression guard against a future refactor
  /// pointing the scan at the wrong directory.
  @Test func orphanedModelFiles_ignoresCachesPartialDownload() throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])
    let partialURL = sut.downloadFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x42, count: 128).write(to: partialURL)
    defer { try? FileManager.default.removeItem(at: partialURL) }

    let orphans = sut.orphanedModelFiles()
    #expect(!orphans.contains { $0.fileName == partialURL.lastPathComponent })
  }

  /// `deleteOrphanedFile(fileName:)` removes the on-disk orphan.
  @Test func deleteOrphanedFile_removesOrphan() throws {
    let sut = makeSUT(catalog: [makeTestDescriptor()])
    try FileManager.default.createDirectory(
      at: sut.modelDirectoryURL, withIntermediateDirectories: true)
    let orphanName = "superseded-\(UUID().uuidString).gguf"
    let orphanURL = sut.modelDirectoryURL.appendingPathComponent(orphanName)
    try Data(repeating: 0x42, count: 32).write(to: orphanURL)
    defer { try? FileManager.default.removeItem(at: orphanURL) }

    sut.deleteOrphanedFile(fileName: orphanName)
    #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
  }

  /// `deleteOrphanedFile(fileName:)` is a no-op when the name matches a
  /// catalog entry — the catalog-membership guard transitively protects
  /// the active model from deletion via this path.
  @Test func deleteOrphanedFile_noopForCatalogFileName() throws {
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(catalog: [descriptor])
    let modelURL = sut.modelFileURL(for: descriptor)
    try FileManager.default.createDirectory(
      at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x42, count: 16).write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: modelURL) }

    sut.deleteOrphanedFile(fileName: descriptor.fileName)
    #expect(FileManager.default.fileExists(atPath: modelURL.path))
  }
}
