import Foundation

/// Pure presentation logic for `ActiveModelChip` — derives the chip's display
/// label, status-dot semantics, and the inline-switch menu rows from a
/// value-typed snapshot of `ModelManager` state.
///
/// Lives in Views/ for proximity to the consuming view but takes a plain
/// snapshot (no `ModelManager` dependency) so the test suite is fully
/// deterministic. Marked `nonisolated` so the initializer and `Equatable`
/// conformance are callable from test code without a `MainActor` context —
/// same pattern as `RecommendedModelStatus`.
///
/// Semantics only, no SwiftUI / no user-facing copy: the view maps `StatusDot`
/// to a `Color` token and `MenuRow.Detail` to localized text, keeping this type
/// copy-free and unit-testable (ADR-009 / view-testing).
nonisolated struct ActiveModelChipPresenter: Equatable {
  /// Status-dot semantics for the active model. The view maps each case to a
  /// design-system color token.
  enum StatusDot: Equatable {
    /// Active model is downloaded and loadable — `Color.mossDark`.
    case ready
    /// Active model is downloading — `Color.warning`.
    case working
    /// Transient / not-yet-downloaded — `Color.muted`.
    case inactive
    /// Errored or unsupported device — `Color.danger`.
    case problem
  }

  /// One inline-switch menu entry, one per catalog model.
  struct MenuRow: Equatable, Identifiable {
    let id: ModelID
    /// The model's own display name (`shortDisplayName ?? displayName`) — model
    /// data, not app copy.
    let name: String
    /// True for the currently-active model (rendered with a checkmark).
    let isActive: Bool
    /// True only when the model is `.ready` AND no simulation is in flight —
    /// mirrors `ModelSettingsRow.isSwitchLocked`. Non-selectable rows are
    /// disabled in the menu.
    let isSelectable: Bool
    /// Trailing detail for a non-ready row (explains why it is disabled);
    /// `nil` for a ready model — the switch menu shows just the name. Download
    /// size is deliberately omitted: it informs the download decision (a
    /// Settings-time concern), not the choice of which downloaded model to run.
    let detail: RowDetail?
  }

  /// Trailing per-row detail for non-ready models — an availability hint the
  /// view localizes. Kept at the presenter level (not nested in `MenuRow`) to
  /// stay within SwiftLint's 1-level nesting cap.
  enum RowDetail: Equatable {
    case downloading
    case notDownloaded
    case unavailable
  }

  /// The active model's display name, or `nil` when no model is active yet
  /// (pre-onboarding edge — the chip is only mounted post-onboarding).
  let chipLabel: String?
  let statusDot: StatusDot
  let rows: [MenuRow]

  init(
    activeDescriptor: ModelDescriptor?,
    activeState: ModelState,
    catalog: [ModelDescriptor],
    state: [ModelID: ModelState],
    activeModelID: ModelID,
    isSimulationActive: Bool
  ) {
    chipLabel = activeDescriptor.map { $0.shortDisplayName ?? $0.displayName }
    statusDot = Self.statusDot(for: activeState)
    rows = catalog.map { descriptor in
      // A model absent from `state` has not been classified yet — treat as
      // `.checking` (matches the Settings rows' `?? .checking` fallback).
      let modelState = state[descriptor.id] ?? .checking
      return MenuRow(
        id: descriptor.id,
        name: descriptor.shortDisplayName ?? descriptor.displayName,
        isActive: descriptor.id == activeModelID,
        isSelectable: Self.isReady(modelState) && !isSimulationActive,
        detail: Self.detail(for: modelState)
      )
    }
  }

  static func statusDot(for state: ModelState) -> StatusDot {
    switch state {
    case .ready: .ready
    case .downloading: .working
    case .checking, .notDownloaded: .inactive
    case .error, .unsupportedDevice: .problem
    }
  }

  static func detail(for state: ModelState) -> RowDetail? {
    switch state {
    case .ready: nil
    case .downloading: .downloading
    case .notDownloaded: .notDownloaded
    case .checking, .error, .unsupportedDevice: .unavailable
    }
  }

  private static func isReady(_ state: ModelState) -> Bool {
    if case .ready = state { return true }
    return false
  }
}
