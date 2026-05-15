import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ModelSelectionStateTests {

  // MARK: - Helpers

  /// Builds a state with the production Gemma + Qwen catalog and a
  /// configurable initial selection / storage probe. Tests that need
  /// custom descriptors can construct directly.
  func makeState(
    selected: ModelID = ModelRegistry.gemma4E2B.id,
    availableStorageBytes: Int64? = nil
  ) -> ModelSelectionState {
    ModelSelectionState(
      selected: selected,
      recommendedID: ModelRegistry.recommendedModelID,
      availableModels: ModelRegistry.catalog,
      availableStorageBytes: availableStorageBytes
    )
  }

  // MARK: - selectedDescriptor

  @Test func selectedDescriptor_returnsMatching_whenIDIsInCatalog() {
    let state = makeState(selected: ModelRegistry.qwen34B.id)
    #expect(state.selectedDescriptor?.id == ModelRegistry.qwen34B.id)
  }

  /// `selected` outside the catalog should never happen in production —
  /// the picker installs `recommendedID` at start and only flips on row
  /// taps — but the derived getter returns `nil` rather than crashing.
  /// Asserts the defensive shape so a future regression doesn't promote
  /// this to a force-unwrap.
  @Test func selectedDescriptor_returnsNil_whenIDIsNotInCatalog() {
    let state = makeState(selected: "no-such-model")
    #expect(state.selectedDescriptor == nil)
  }

  // MARK: - isLowStorage

  @Test func isLowStorage_returnsFalse_whenStorageProbeIsNil() {
    let state = makeState(availableStorageBytes: nil)
    #expect(!state.isLowStorage)
  }

  /// Gemma is 3_106_735_776 bytes. With margin 1_000_000_000, the threshold
  /// is 4_106_735_776. Plant available exactly one byte below to assert
  /// the predicate fires at the boundary (the `<` shape).
  @Test func isLowStorage_returnsTrue_whenStorageJustBelowThreshold() {
    let state = makeState(availableStorageBytes: 3_106_735_776 + 1_000_000_000 - 1)
    #expect(state.isLowStorage)
  }

  @Test func isLowStorage_returnsFalse_whenStorageAtThreshold() {
    let state = makeState(availableStorageBytes: 3_106_735_776 + 1_000_000_000)
    #expect(!state.isLowStorage)
  }

  // MARK: - handleDownloadTap

  /// Normal flow: storage is fine → returns false, no pending sheet.
  /// The host View takes this as "proceed to startDownload".
  @Test func handleDownloadTap_returnsFalse_whenStorageOk() {
    let state = makeState(availableStorageBytes: 10_000_000_000)
    let queued = state.handleDownloadTap()
    #expect(!queued)
    #expect(state.pendingStorageWarning == nil)
  }

  /// Low-storage path: returns true AND sets `pendingStorageWarning`
  /// to the selected descriptor. The View's `.sheet(item:)` then
  /// presents automatically.
  @Test func handleDownloadTap_queuesWarning_whenLowStorage() {
    let state = makeState(
      selected: ModelRegistry.qwen34B.id,
      availableStorageBytes: 100)
    let queued = state.handleDownloadTap()
    #expect(queued)
    #expect(state.pendingStorageWarning?.id == ModelRegistry.qwen34B.id)
  }

  // MARK: - Sheet button handlers

  @Test func cancelStorageWarning_clearsPending() {
    let state = makeState(availableStorageBytes: 100)
    _ = state.handleDownloadTap()  // queue the sheet
    state.cancelStorageWarning()
    #expect(state.pendingStorageWarning == nil)
  }

  @Test func acceptStorageWarning_clearsPendingAndReturnsDescriptor() {
    let state = makeState(
      selected: ModelRegistry.gemma4E2B.id,
      availableStorageBytes: 100)
    _ = state.handleDownloadTap()
    let accepted = state.acceptStorageWarning()
    #expect(accepted?.id == ModelRegistry.gemma4E2B.id)
    #expect(state.pendingStorageWarning == nil)
  }
}
