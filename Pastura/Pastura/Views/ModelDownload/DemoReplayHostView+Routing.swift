import Foundation
import os

/// Pure routing decisions for `DemoReplayHostView`.
///
/// State-to-view dispatch (`stateView(state:demosCount:replayHadStarted:requiresCellularConsent:)`)
/// lives in `DemoReplayHostView+StateFallbacks.swift` next to the
/// per-state UI helpers it returns; ``readyDispatch(showsCompleteOverlay:hasReplayVM:)``
/// stays here because it has no UI of its own. Both are pure for unit
/// testability — exercised by `DemoReplayHostViewTests`.
extension DemoReplayHostView {

  // MARK: - Ready dispatch

  /// Outcome of the `.ready` arrival gating logic, returned by
  /// ``readyDispatch(showsCompleteOverlay:hasReplayVM:)``.
  enum ReadyDispatch: Equatable {
    /// Settings cover path. Caller invokes `onComplete?()`.
    case fireOnComplete
    /// First-launch slot.
    /// - `awaitsTap == true`: overlay will render — flip the VM into
    ///   `.transitioning`, store `modelPath`, and wait for the user
    ///   to tap on `DLCompleteOverlay` before invoking `onReady?(modelPath)`.
    /// - `awaitsTap == false`: no overlay can render (sub-floor demo
    ///   count or VM failed to construct), so fire `onReady?(modelPath)`
    ///   immediately.
    case fireOnReady(awaitsTap: Bool)
  }

  /// Decides how to react to `ModelState == .ready` based on the
  /// presentation context and whether an overlay would render.
  ///
  /// `reduceMotion` is intentionally NOT a parameter: the overlay
  /// itself respects reduce-motion (snaps to full opacity instead of
  /// fading), but the dispatch decision (await tap vs fire immediately)
  /// is the same either way — the user still needs to acknowledge the
  /// "Ready" beat by tapping.
  static func readyDispatch(
    showsCompleteOverlay: Bool,
    hasReplayVM: Bool
  ) -> ReadyDispatch {
    if !showsCompleteOverlay { return .fireOnComplete }
    // No overlay can render without a VM (the overlay reads
    // `viewModel.state == .transitioning`). Fire immediately on those
    // paths so sub-floor / VM-failed-to-construct users don't sit
    // through a meaningless tap-prompt for an invisible UI.
    guard hasReplayVM else { return .fireOnReady(awaitsTap: false) }
    return .fireOnReady(awaitsTap: true)
  }

  // MARK: - Logger

  /// Shared `os.Logger` for the host view. Used by `initialLoad` to
  /// surface diagnostic data through Console.app — filter by subsystem
  /// `com.tyabu12.Pastura` category `DemoReplayHostView`.
  static let logger = Logger(
    subsystem: "com.tyabu12.Pastura", category: "DemoReplayHostView")
}
