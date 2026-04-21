import SwiftUI

/// Host view for the DL-time demo replay feature.
///
/// Replaces `ModelDownloadView` in the `.needsModelDownload` slot (wiring
/// lands in PR3). Decides between the demo host body and the plain
/// `ModelDownloadView` fallback based on cellular reachability, model
/// state, bundled demo count, and whether replay has already started —
/// see ``fallbackBranch(state:demosCount:replayHadStarted:isCellular:)``.
///
/// The chat stream binding and lifecycle (`.task`, scene-phase bridge,
/// `DLCompleteOverlay`) are added in items 6/7 of PR2.
struct DemoReplayHostView: View {
  let modelManager: ModelManager

  /// Minimum number of validated bundled demos required to render the
  /// demo host. Below this floor we defer to `ModelDownloadView` — the
  /// rotation loop is unsatisfying with a single demo (spec §5.2).
  static let minPlayableDemoCount = 2

  @State private var replayVM: ReplayViewModel?
  @State private var replayHadStarted: Bool = false
  @State private var isCellular: Bool = false
  @State private var sources: [any ReplaySource] = []

  var body: some View {
    switch Self.fallbackBranch(
      state: modelManager.state,
      demosCount: sources.count,
      replayHadStarted: replayHadStarted,
      isCellular: isCellular) {
    case .modelDownload:
      ModelDownloadView(modelManager: modelManager)
    case .demoHost:
      demoHostBody
    }
  }

  @ViewBuilder
  private var demoHostBody: some View {
    // Placeholder — chat stream (item 6), lifecycle + DLCompleteOverlay
    // (item 7) land in follow-up commits of PR2.
    Color.screenBackground
      .ignoresSafeArea()
  }

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
}

// MARK: - Previews

// Only the default (checking) preview is exercised at skeleton time:
// `ModelManager.state` is `private(set)`, so seeding arbitrary states
// for preview would require a production seam. Richer preview variants
// land once item 7 wires the real `.task { }` load; for now the
// `fallbackBranch` decision is covered by unit tests in item 8.
#Preview {
  DemoReplayHostView(modelManager: ModelManager())
}
