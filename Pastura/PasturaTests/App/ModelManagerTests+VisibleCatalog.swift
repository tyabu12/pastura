import Foundation
import Testing

@testable import Pastura

// `ModelManager.visibleCatalog` — the ADD-and-keep display filter (#1487).
//
// An extension of `ModelManagerTests` rather than a new `@Suite`, per
// .claude/rules/testing.md: a sibling suite would run in parallel and race the
// original on the shared model file path under Application Support.
//
// Every case here drives `checkModelStatus()` (or deliberately does not) rather
// than writing `state` directly, so the `.notDownloaded` these assert is the one
// production computes.
extension ModelManagerTests {

  /// Two descriptors whose second replaces the first. Distinct `fileName`s —
  /// `computeState` keys on the filename, so sharing one would make both entries
  /// resolve to the same on-disk file and quietly couple their states.
  private func makeReplacementPair() -> (legacy: ModelDescriptor, newer: ModelDescriptor) {
    let legacy = makeTestDescriptor(id: "legacy-model", fileName: "legacy-model.gguf")
    let newer = makeTestDescriptor(
      id: "newer-model", fileName: "newer-model.gguf", replacesModelID: legacy.id)
    return (legacy, newer)
  }

  @Test("visibleCatalog hides a replaced entry that is not on disk")
  func visibleCatalogHidesReplacedEntryWhenNotDownloaded() {
    let (legacy, newer) = makeReplacementPair()
    // `newer` first, so `resolveInitialActiveID`'s catalog-first fallback makes
    // it active and `legacy` is free to hide.
    let sut = makeSUT(catalog: [newer, legacy])

    sut.checkModelStatus()

    #expect(sut.state[legacy.id] == .notDownloaded)
    #expect(sut.visibleCatalog.map(\.id) == ["newer-model"])
  }

  /// Negative control for the case above. Same catalog shape, same
  /// `.notDownloaded` states, `replacesModelID` removed — nothing may hide. Without
  /// this arm the assertion above would also pass if `visibleCatalog` hid every
  /// not-downloaded entry, which is a different and much worse filter.
  @Test("visibleCatalog hides nothing when no entry replaces another")
  func visibleCatalogKeepsEverythingWhenNothingIsReplaced() {
    let first = makeTestDescriptor(id: "legacy-model", fileName: "legacy-model.gguf")
    let second = makeTestDescriptor(id: "newer-model", fileName: "newer-model.gguf")
    let sut = makeSUT(catalog: [second, first])

    sut.checkModelStatus()

    #expect(sut.state[first.id] == .notDownloaded)
    #expect(sut.visibleCatalog.map(\.id) == ["newer-model", "legacy-model"])
  }

  @Test("visibleCatalog keeps a replaced entry that is on disk")
  func visibleCatalogKeepsReplacedEntryWhenOnDisk() throws {
    let (legacy, newer) = makeReplacementPair()
    let sut = makeSUT(catalog: [newer, legacy])

    let modelPath = sut.modelFileURL(for: legacy)
    try FileManager.default.createDirectory(
      at: modelPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelPath.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: modelPath) }

    sut.checkModelStatus()

    #expect(sut.visibleCatalog.map(\.id) == ["newer-model", "legacy-model"])
  }

  /// The third conjunct. `computeState` deletes a size-mismatched file and
  /// returns `.notDownloaded`, so an active-but-corrupted replaced build hits
  /// exactly this shape — and hiding it would leave the user with no row to
  /// re-download from and no menu entry to switch away to.
  @Test("visibleCatalog keeps the active entry even when it is not on disk")
  func visibleCatalogKeepsActiveReplacedEntryWhenNotDownloaded() {
    let (legacy, newer) = makeReplacementPair()
    // `legacy` first, so the catalog-first fallback makes the replaced entry the
    // active one.
    let sut = makeSUT(catalog: [legacy, newer])

    sut.checkModelStatus()

    #expect(sut.activeModelID == legacy.id)
    #expect(sut.state[legacy.id] == .notDownloaded)
    #expect(sut.visibleCatalog.map(\.id) == ["legacy-model", "newer-model"])
  }

  /// `.checking` must not hide: Settings renders live, so a filter that fired on
  /// the transient state would flicker rows out for a frame on every appearance.
  /// No `checkModelStatus()` call — `init` seeds every entry `.checking`.
  @Test("visibleCatalog keeps a replaced entry while its state is still checking")
  func visibleCatalogKeepsReplacedEntryWhileChecking() {
    let (legacy, newer) = makeReplacementPair()
    let sut = makeSUT(catalog: [newer, legacy])

    #expect(sut.state[legacy.id] == .checking)
    #expect(sut.visibleCatalog.map(\.id) == ["newer-model", "legacy-model"])
  }

  /// The production catalog's own invariant: whatever `visibleCatalog` hides, it
  /// must never hide the model a new install is steered toward. Both id
  /// constants are asserted independently — they alias today, and
  /// `ModelRegistryTests` deliberately refuses to pin them equal.
  ///
  /// The `replacement(for:) == nil` pair is the load-bearing half. The
  /// `visibleCatalog` membership arms are an end-to-end echo of it, but they run
  /// against the real model directory, so on a machine that happens to have the
  /// replaced build on disk they would pass for the wrong reason; the
  /// state-free pair holds regardless.
  @Test("the recommended and default-initial models survive the production filter")
  func productionRecommendedAndDefaultModelsAreVisible() {
    let sut = makeSUT(catalog: ModelRegistry.catalog)
    sut.checkModelStatus()
    // Move the active model off both constants first. With empty defaults
    // `resolveInitialActiveID` lands on `defaultInitialModelID`, and conjunct 3
    // keeps the *active* entry visible unconditionally — so without this the
    // `defaultInitialModelID` arm below could not fail for any in-catalog value,
    // including one repointed at a replaced build. Measured: it passed that way.
    sut.setActiveModel(ModelRegistry.qwen34B.id)

    #expect(
      ModelRegistry.replacement(
        for: ModelRegistry.recommendedModelID, in: ModelRegistry.catalog) == nil)
    #expect(
      ModelRegistry.replacement(
        for: ModelRegistry.defaultInitialModelID, in: ModelRegistry.catalog) == nil)

    let visible = Set(sut.visibleCatalog.map(\.id))
    #expect(visible.contains(ModelRegistry.recommendedModelID))
    #expect(visible.contains(ModelRegistry.defaultInitialModelID))
  }
}
