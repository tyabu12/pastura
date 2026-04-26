import Foundation

/// Pure routing decisions for `DemoReplayHostView`:
/// - ``fallbackBranch(state:demosCount:replayHadStarted:isCellular:)``
///   chooses between the demo host and the plain `ModelDownloadView`.
/// - ``readyDispatch(showsCompleteOverlay:hasReplayVM:reduceMotion:)``
///   decides what to do on `ModelState == .ready` arrival.
///
/// Lives in a sibling file to keep the host view's main file under
/// swiftlint's 400-line `file_length` cap. Both functions are pure
/// for unit testability — exercised by `DemoReplayHostViewTests`.
extension DemoReplayHostView {

  // MARK: - Fallback decision

  enum Branch: Equatable {
    case modelDownload
    case demoHost
  }

  /// Routes between the plain download UI and the demo host.
  ///
  /// Cellular acts as a conservative safety net (ADR-007 §3.3 (c) Option
  /// A — full cellular modal UX is tracked as #191). Below the
  /// minimum-playable floor we defer to `ModelDownloadView` so a single
  /// surviving demo doesn't render with a nil VM. On `.error` we keep
  /// replay alive only if it had already started, mirroring ADR-007
  /// §3.3 (b) — the progress bar area swaps to inline retry inside
  /// `PromoCard` while playback continues.
  static func fallbackBranch(
    state: ModelState,
    demosCount: Int,
    replayHadStarted: Bool,
    isCellular: Bool
  ) -> Branch {
    if isCellular { return .modelDownload }
    switch state {
    case .checking, .unsupportedDevice, .notDownloaded:
      return .modelDownload
    case .downloading:
      return demosCount >= minPlayableDemoCount ? .demoHost : .modelDownload
    case .error:
      return replayHadStarted ? .demoHost : .modelDownload
    case .ready:
      return .demoHost
    }
  }

  // MARK: - Ready dispatch

  /// Outcome of the `.ready` arrival gating logic, returned by
  /// ``readyDispatch(showsCompleteOverlay:hasReplayVM:reduceMotion:)``.
  enum ReadyDispatch: Equatable {
    /// Settings cover path. Caller invokes `onComplete?()`.
    case fireOnComplete
    /// First-launch slot. Caller waits `waitMs`, then invokes
    /// `onReady?(modelPath)`. `waitMs == 0` means fire immediately
    /// without spinning a Task.
    case fireOnReady(waitMs: Int)
  }

  /// Decides how to react to `ModelState == .ready` based on the
  /// presentation context and whether an overlay would render.
  ///
  /// Pure function — extracted for unit testability mirroring
  /// ``fallbackBranch(state:demosCount:replayHadStarted:isCellular:)``.
  /// The wait values are sourced from `DLCompleteOverlay`'s timing
  /// constants so the overlay animation and the upstream wait can't
  /// drift apart.
  static func readyDispatch(
    showsCompleteOverlay: Bool,
    hasReplayVM: Bool,
    reduceMotion: Bool
  ) -> ReadyDispatch {
    if !showsCompleteOverlay { return .fireOnComplete }
    // No overlay can render without a VM (the overlay reads
    // `viewModel.state == .transitioning`). Fire immediately on those
    // paths so cellular / sub-floor / VM-failed-to-construct users
    // don't sit through a meaningless wait.
    guard hasReplayVM else { return .fireOnReady(waitMs: 0) }
    if reduceMotion {
      return .fireOnReady(waitMs: DLCompleteOverlay.reducedMotionHoldMs)
    }
    return .fireOnReady(waitMs: DLCompleteOverlay.totalAnimationMs)
  }
}
