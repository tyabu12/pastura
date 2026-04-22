import Network
import SwiftUI

/// Host view for the DL-time demo replay feature.
///
/// Replaces `ModelDownloadView` in the `.needsModelDownload` slot (wiring
/// lands in PR3). Decides between the demo host body and the plain
/// `ModelDownloadView` fallback based on cellular reachability, model
/// state, bundled demo count, and whether replay has already started —
/// see ``fallbackBranch(state:demosCount:replayHadStarted:isCellular:)``.
///
/// Lifecycle:
/// - On first appearance, `.task { }` runs a 1-shot `NWPathMonitor`
///   check. If cellular, the view stays in the fallback branch (Option A
///   safety net — full modal UX is #191). Otherwise it enumerates
///   bundled demos via `BundledDemoReplaySource.loadAll(...)`, and if
///   at least `minPlayableDemoCount` demos validate, constructs a
///   `ReplayViewModel` and calls `start()`.
/// - `scenePhase` is bridged to `onBackground() / onForeground()`
///   per ADR-007 §3.3 (a).
/// - `ModelState.ready` triggers `downloadComplete()` on the VM, which
///   flips its state to `.transitioning`; `DLCompleteOverlay` then fades
///   in over the chat stream.
///
/// `.task` is safe to leave on the outer view body: `AppState` does not
/// change on `ModelManager.state` transitions within the
/// `.needsModelDownload` slot (see `PasturaApp.swift`), so the view's
/// SwiftUI identity is preserved and `.task` runs exactly once per
/// host-view mount.
struct DemoReplayHostView: View {
  let modelManager: ModelManager

  /// Minimum number of validated bundled demos required to render the
  /// demo host. Below this floor we defer to `ModelDownloadView` — the
  /// rotation loop is unsatisfying with a single demo (spec §5.2).
  static let minPlayableDemoCount = 2

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var replayVM: ReplayViewModel?
  @State private var replayHadStarted: Bool = false
  @State private var isCellular: Bool = false
  @State private var sources: [any ReplaySource] = []

  var body: some View {
    currentView
      .task { await initialLoad() }
      .onChange(of: scenePhase) { _, newPhase in
        handleScenePhase(newPhase)
      }
      .onChange(of: modelManager.state) { _, newState in
        handleModelStateChange(newState)
      }
  }

  @ViewBuilder
  private var currentView: some View {
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
    if let viewModel = replayVM {
      chatStream(viewModel: viewModel)
        .overlay {
          if viewModel.state == .transitioning {
            DLCompleteOverlay()
          }
        }
    } else {
      // Until `.task { }` resolves the cellular check + finishes loading
      // sources, render an empty background. The fallbackBranch routes
      // away from the demo host before this nil state is reached once
      // `isCellular`/`sources` update.
      Color.screenBackground.ignoresSafeArea()
    }
  }

  private func chatStream(viewModel: ReplayViewModel) -> some View {
    ZStack(alignment: .bottom) {
      Color.screenBackground.ignoresSafeArea()

      VStack(spacing: 0) {
        PhaseHeader(
          presetName: currentPresetName(viewModel: viewModel).uppercased(),
          phaseLabel: currentPhaseLabel(viewModel: viewModel))

        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
              ForEach(viewModel.agentOutputs) { entry in
                AgentOutputRow(
                  agent: entry.agent,
                  output: entry.output,
                  phaseType: entry.phaseType,
                  showAllThoughts: true,
                  isLatest: entry.id == viewModel.agentOutputs.last?.id,
                  charsPerSecond: 60
                )
                .id(entry.id)
                .transition(reduceMotion ? .identity : .opacity)
              }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // Space for the PromoCard overlay (bottom: 22pt + card height).
            .padding(.bottom, 160)
            .animation(
              reduceMotion ? nil : .easeOut(duration: 0.7),
              value: viewModel.agentOutputs.count)
          }
          .onChange(of: viewModel.agentOutputs.count) { _, _ in
            guard let lastId = viewModel.agentOutputs.last?.id else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
              proxy.scrollTo(lastId, anchor: .bottom)
            }
          }
        }
      }

      PromoCard(
        modelState: modelManager.state,
        replayHadStarted: replayHadStarted,
        onRetry: { modelManager.startDownload() })
    }
  }

  private func currentPresetName(viewModel: ReplayViewModel) -> String {
    guard case .playing(let sourceIndex, _) = viewModel.state,
      sourceIndex < sources.count
    else { return "" }
    return sources[sourceIndex].scenario.name
  }

  private func currentPhaseLabel(viewModel: ReplayViewModel) -> String {
    guard let phase = viewModel.currentPhase else { return "" }
    let base = phase.rawValue
    if let round = viewModel.currentRound {
      return "\(base) \(round)"
    }
    return base
  }

  // MARK: - Lifecycle

  private func initialLoad() async {
    // 1-shot cellular check. Option A safety net — if cellular, we skip
    // loading demos entirely and let the fallback branch route to the
    // plain `ModelDownloadView`. Full modal UX tracked as #191.
    let cellular = await Self.isCellularNow()
    isCellular = cellular
    guard !cellular else { return }

    let loaded = BundledDemoReplaySource.loadAll()
    // `loadAll` enumerates `Resources/DemoReplays/*.yaml` — currently
    // empty pre-#170, so the typical result on main is `[]`.
    sources = loaded
    guard loaded.count >= Self.minPlayableDemoCount else { return }

    let viewModel = ReplayViewModel(sources: loaded)
    replayVM = viewModel
    viewModel.start()
    replayHadStarted = true
  }

  private func handleScenePhase(_ phase: ScenePhase) {
    guard let viewModel = replayVM else { return }
    switch phase {
    case .background, .inactive:
      viewModel.onBackground()
    case .active:
      viewModel.onForeground()
    @unknown default:
      break
    }
  }

  private func handleModelStateChange(_ newState: ModelState) {
    if case .ready = newState {
      replayVM?.downloadComplete()
    }
  }

  /// Reads the current network path once via `NWPathMonitor`. Treats
  /// any "expensive" path as cellular — this covers personal hotspot
  /// and metered Wi-Fi in addition to literal cellular, which is the
  /// desired conservative posture for a 3 GB download safety net.
  private static func isCellularNow() async -> Bool {
    let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      continuation.yield(path.isExpensive)
      continuation.finish()
    }
    monitor.start(queue: .global(qos: .userInitiated))
    defer { monitor.cancel() }
    for await isCellular in stream {
      return isCellular
    }
    return false
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

// MARK: - DLCompleteOverlay

/// Fullscreen overlay shown while `ReplayViewModel.state == .transitioning`.
///
/// Per `demo-replay-ui.md` §DLCompleteOverlay: ultra-thin material
/// background + pulsing 44 pt dog mark + "準備ができました" +
/// "tap anywhere to begin". Spec §2 decision 6 / 8 makes the transition
/// auto-only — the hint text is visual only and no tap handler is wired.
///
/// Fade-in is `.easeOut(2.4s, delay: 0.2s)` by default. Under
/// `accessibilityReduceMotion`, the overlay is shown at full opacity
/// immediately and the dog mark does not pulse (handled inside
/// `DogMark.pulsing()`).
private struct DLCompleteOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()

      VStack(spacing: Spacing.s) {
        DogMark(size: 44)
          .pulsing()
        Text("準備ができました")
          .textStyle(Typography.statusComplete)
          .foregroundStyle(Color.mossInk)
        Text("tap anywhere to begin")
          .textStyle(Typography.statusHint)
          .foregroundStyle(Color.muted)
      }
    }
    .opacity(hasAppeared || reduceMotion ? 1 : 0)
    .onAppear {
      guard !reduceMotion else {
        hasAppeared = true
        return
      }
      withAnimation(.easeOut(duration: 2.4).delay(0.2)) {
        hasAppeared = true
      }
    }
  }
}

// MARK: - Previews

// The outer view exercises the default (`.checking` → fallback) path.
// `ModelManager.state` is `private(set)`, so richer variants would
// require a production seam; the `fallbackBranch` pure function is
// unit-tested instead (item 8).
#Preview {
  DemoReplayHostView(modelManager: ModelManager())
}

#Preview("DLCompleteOverlay") {
  ZStack {
    Color.screenBackground.ignoresSafeArea()
    DLCompleteOverlay()
  }
}
