import Foundation
import Observation

/// Observable state for the first-launch model picker.
///
/// Owned by `ModelPickerView` as `@State`. Holds the user's current
/// selection, the recommended-badge source-of-truth, and the
/// derived low-storage warning state.
///
/// ## Scope discipline
///
/// `availableStorageBytes` is seeded once by the host View via
/// `state.availableStorageBytes = modelManager.availableStorageBytes()`
/// inside `.onAppear`. The state never touches `FileManager` directly —
/// the actual capacity probe lives on `ModelManager` (App layer
/// charter, see `ModelManager.swift` § "Storage").
///
/// `reduceMotion` is NOT a field on this state. The host View reads
/// `@Environment(\.accessibilityReduceMotion)` and forwards it to
/// `ModelSelectionAnimations` per animation call site. See that file's
/// header for the rationale.
@Observable
final class ModelSelectionState {

  // MARK: - Identity

  /// Currently-selected model id. Initialized to `recommendedID` for
  /// new users; flipped by row taps. Always a valid id in
  /// `availableModels`.
  var selected: ModelID

  /// The "推奨" badge anchor. Read by `ModelRow` to decide whether to
  /// render the tag. Constant for the lifetime of the picker session.
  let recommendedID: ModelID

  /// The models the picker presents. Constant for the lifetime of the
  /// picker session — change of catalog implies re-creating the state.
  let availableModels: [ModelDescriptor]

  // MARK: - Storage warning

  /// Most recent free-space probe for the model directory volume, in
  /// bytes. `nil` until the host View seeds it from
  /// `ModelManager.availableStorageBytes()` (or the volume reports no
  /// capacity, in which case `isLowStorage` stays `false` — see the
  /// pure helper for the rationale).
  var availableStorageBytes: Int64?

  /// Descriptor whose low-storage warning sheet should present.
  /// Non-nil → sheet visible; setting to `nil` dismisses.
  ///
  /// Lives as `ModelDescriptor?` (not `Bool`) so the sheet body can
  /// receive the descriptor directly via `.sheet(item:)` and avoid
  /// re-reading `selected` (which the user could in principle change
  /// between the CTA tap and the sheet's appearance — defensive even
  /// if the picker disables row taps while the sheet is up).
  var pendingStorageWarning: ModelDescriptor?

  // MARK: - Init

  init(
    selected: ModelID,
    recommendedID: ModelID,
    availableModels: [ModelDescriptor],
    availableStorageBytes: Int64? = nil
  ) {
    self.selected = selected
    self.recommendedID = recommendedID
    self.availableModels = availableModels
    self.availableStorageBytes = availableStorageBytes
  }

  // MARK: - Derived

  /// Descriptor for `selected`, or `nil` if `selected` is somehow not
  /// in `availableModels` (programmer error — the catalog is fixed
  /// for the picker session).
  var selectedDescriptor: ModelDescriptor? {
    availableModels.first { $0.id == selected }
  }

  /// True iff the free-space probe is non-nil AND below the safety
  /// margin for the selected model. Delegates the threshold logic to
  /// `ModelManager.isLowStorage(...)` so the warning predicate has
  /// a single source-of-truth.
  var isLowStorage: Bool {
    guard let descriptor = selectedDescriptor else { return false }
    return ModelManager.isLowStorage(
      modelSizeBytes: descriptor.fileSize,
      availableBytes: availableStorageBytes
    )
  }

  // MARK: - Actions

  /// CTA tap handler. Returns `true` iff the storage warning sheet was
  /// queued (i.e., the host View should NOT start a download
  /// immediately and should let the user resolve the warning first).
  ///
  /// Mutates `pendingStorageWarning` on the warn path so the host's
  /// `.sheet(item:)` automatically presents.
  @discardableResult
  func handleDownloadTap() -> Bool {
    guard let descriptor = selectedDescriptor else { return false }
    if isLowStorage {
      pendingStorageWarning = descriptor
      return true
    }
    return false
  }

  /// Called from `StorageWarningSheet`'s "Cancel" button. Dismisses
  /// the sheet without starting a download.
  func cancelStorageWarning() {
    pendingStorageWarning = nil
  }

  /// Called from `StorageWarningSheet`'s "Download anyway" button.
  /// Dismisses the sheet so the host can call `modelManager.startDownload(...)`.
  /// Returns the descriptor the user committed to so the caller doesn't
  /// have to re-read `pendingStorageWarning` post-mutation.
  @discardableResult
  func acceptStorageWarning() -> ModelDescriptor? {
    let descriptor = pendingStorageWarning
    pendingStorageWarning = nil
    return descriptor
  }
}
