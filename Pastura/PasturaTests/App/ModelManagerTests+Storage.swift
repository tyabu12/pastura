import Foundation
import Testing

@testable import Pastura

// MARK: - Storage helpers

// `isLowStorage` is a `nonisolated static` pure function so tests can call
// it from any context. The SUT helper paths (sibling-file extensions calling
// `makeSUT` / `makeTestDescriptor` defined in `ModelManagerTests.swift`)
// require these helpers to be `internal` rather than `private` — see
// `.claude/rules/testing.md` § "Splitting a Suite Across Files".
extension ModelManagerTests {

  // MARK: - isLowStorage (pure-input)

  /// Available capacity strictly below `modelSize + margin` → returns `true`
  /// (warn). The margin is documented in `ModelManager.isLowStorage` itself
  /// (currently 1 GB). The test plants the boundary minus one byte so a
  /// future revert of the `<` to `<=` comparison would surface here.
  @Test func isLowStorage_warnsWhenAvailableJustBelowMargin() {
    let modelSize: Int64 = 3_000_000_000
    let safetyMargin: Int64 = 1_000_000_000
    let available: Int64 = (modelSize + safetyMargin) - 1
    #expect(ModelManager.isLowStorage(modelSizeBytes: modelSize, availableBytes: available))
  }

  /// Available capacity at the boundary (`modelSize + margin`) is exactly
  /// "enough" — no warning. The pair with the previous test guards against
  /// off-by-one regressions when the comparison operator is touched.
  @Test func isLowStorage_silentAtExactBoundary() {
    let modelSize: Int64 = 3_000_000_000
    let safetyMargin: Int64 = 1_000_000_000
    let available: Int64 = modelSize + safetyMargin
    #expect(!ModelManager.isLowStorage(modelSizeBytes: modelSize, availableBytes: available))
  }

  /// `availableBytes == nil` (volume reports no capacity) falls through to
  /// "no warning" rather than warning conservatively. We trust the OS not
  /// to block downloads when iOS chose not to expose a capacity figure;
  /// the alternative (warn on nil) would noise-up corp-managed devices
  /// and external volumes. Doc-comment on `isLowStorage` carries this
  /// rationale so the choice survives a future read.
  @Test func isLowStorage_silentWhenAvailableNil() {
    #expect(!ModelManager.isLowStorage(modelSizeBytes: 3_000_000_000, availableBytes: nil))
  }

  // MARK: - availableStorageBytes (smoke)

  /// `availableStorageBytes()` is a thin shim over
  /// `URLResourceValues.volumeAvailableCapacityForImportantUsage`. On a
  /// real simulator volume the value is non-nil and positive; this smoke
  /// test only asserts the shim returns without crashing and produces a
  /// non-negative value when capacity is reported. The threshold-logic
  /// regression coverage lives in the `isLowStorage` tests above.
  @Test func availableStorageBytes_returnsNonNegativeOrNil() {
    let sut = makeSUT(catalog: [makeTestDescriptor()])
    if let available = sut.availableStorageBytes() {
      #expect(available >= 0)
    }
  }

  // MARK: - totalModelStorageBytes (pure-input)

  /// Empty inputs sum to zero — the "no models downloaded, no orphans"
  /// baseline the Settings aggregate line renders as "0 GB".
  @Test func totalModelStorageBytes_emptyInputsSumToZero() {
    #expect(ModelManager.totalModelStorageBytes(readyDescriptorSizes: [], orphanSizes: []) == 0)
  }

  /// Ready-descriptor (declared) sizes and orphan (actual) sizes are summed
  /// together — the aggregate counts both completed catalog models and
  /// superseded leftovers.
  @Test func totalModelStorageBytes_sumsReadyAndOrphanSizes() {
    let total = ModelManager.totalModelStorageBytes(
      readyDescriptorSizes: [100, 200], orphanSizes: [50])
    #expect(total == 350)
  }

}
