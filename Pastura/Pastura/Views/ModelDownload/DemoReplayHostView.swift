import Network
import SwiftUI

/// Host view for the DL-time demo replay feature.
///
/// Decides between the demo host body and the plain `ModelDownloadView`
/// fallback based on cellular reachability, descriptor state, bundled
/// demo count, and whether replay has already started — see
/// ``fallbackBranch(state:demosCount:replayHadStarted:isCellular:)``.
///
/// Two presentation contexts:
/// - **`.needsModelDownload` slot** (`PasturaApp.swift`): no cancel UI;
///   on `.ready`, `replayVM.downloadComplete()` runs the in-content
///   `DLCompleteOverlay` while RootView's own state observer transitions
///   to `.ready`.
/// - **Settings → Models cover** (`SettingsView`): caller passes
///   `showsCompleteOverlay: false` + `onComplete` / `onCancel`. On
///   `.ready` the host fires `onComplete` immediately so the cover
///   dismisses without the "tap anywhere to begin" overlay (which has
///   no meaning when returning to a Settings list). `onCancel` reveals
///   a top-trailing X button gated by a confirmation dialog.
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
/// - `.ready` either fires `onComplete` (Settings) or
///   `replayVM.downloadComplete()` (first-launch slot).
///
/// `.task` is safe to leave on the outer view body. Both presentation
/// contexts give the host stable SwiftUI identity for the duration of
/// a single download attempt: `AppState` does not change on
/// `ModelManager.state` transitions within the `.needsModelDownload`
/// slot, and `.fullScreenCover(item:)` keeps the cover content stable
/// for the lifetime of one cover presentation. Re-mount on cover
/// re-presentation (cancel-then-re-tap) is intentional — the fresh
/// `initialLoad()` re-checks cellular + sources without leaking
/// `replayHadStarted` from the prior attempt.
struct DemoReplayHostView: View {
  let modelManager: ModelManager
  let descriptor: ModelDescriptor
  let showsCompleteOverlay: Bool
  let onComplete: (() -> Void)?
  let onCancel: (() -> Void)?

  init(
    modelManager: ModelManager,
    descriptor: ModelDescriptor,
    showsCompleteOverlay: Bool = true,
    onComplete: (() -> Void)? = nil,
    onCancel: (() -> Void)? = nil
  ) {
    self.modelManager = modelManager
    self.descriptor = descriptor
    self.showsCompleteOverlay = showsCompleteOverlay
    self.onComplete = onComplete
    self.onCancel = onCancel
  }

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
  @State private var isShowingCancelConfirmation: Bool = false

  /// Per-descriptor download state. Defaults to `.checking` if the entry is
  /// missing from the state dict (only expected pre-`checkModelStatus`).
  private var currentState: ModelState {
    modelManager.state[descriptor.id] ?? .checking
  }

  var body: some View {
    currentView
      .task { await initialLoad() }
      .onChange(of: scenePhase) { _, newPhase in
        handleScenePhase(newPhase)
      }
      .onChange(of: currentState) { _, newState in
        handleModelStateChange(newState)
      }
      .confirmationDialog(
        String(localized: "Stop downloading?"),
        isPresented: $isShowingCancelConfirmation,
        titleVisibility: .visible
      ) {
        Button(String(localized: "Stop and discard"), role: .destructive) {
          onCancel?()
        }
        Button(String(localized: "Continue downloading"), role: .cancel) {}
      } message: {
        Text(
          String(
            localized:
              "The partial download will be deleted. Resuming later means starting over from the beginning."
          ))
      }
  }

  /// Closure handed to the children that own the visible cancel
  /// affordance (`PromoCard` in the demo branch, `ModelDownloadView`
  /// in the cellular fallback). Returns `nil` when the caller did not
  /// wire `onCancel`, which lets the children hide their cancel UI —
  /// the first-launch slot relies on this to stay uncancellable.
  /// Tapping the affordance flips a `@State` flag here so the host
  /// owns the confirmation dialog; the destructive action eventually
  /// fires `onCancel?()` from inside that dialog.
  private var triggerCancelConfirmation: (() -> Void)? {
    guard onCancel != nil else { return nil }
    return { isShowingCancelConfirmation = true }
  }

  @ViewBuilder
  private var currentView: some View {
    switch Self.fallbackBranch(
      state: currentState,
      demosCount: sources.count,
      replayHadStarted: replayHadStarted,
      isCellular: isCellular) {
    case .modelDownload:
      ModelDownloadView(
        modelManager: modelManager,
        descriptor: descriptor,
        onCancel: triggerCancelConfirmation)
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
    VStack(spacing: 0) {
      PhaseHeader(
        presetName: currentPresetName(viewModel: viewModel).uppercased(),
        phaseLabel: currentPhaseLabel(viewModel: viewModel))

      ScrollViewReader { proxy in
        ScrollView {
          // `spacing` uses the ChatBubbleLayout.bubbleSpacing token so a
          // future design-system tweak flows through both the demo screen
          // and the live SimulationView in one place. Reference HTML
          // `.stream { gap: 14px }`.
          LazyVStack(alignment: .leading, spacing: ChatBubbleLayout.bubbleSpacing) {
            ForEach(viewModel.agentOutputs) { entry in
              AgentOutputRow(
                agent: entry.agent,
                output: entry.output,
                phaseType: entry.phaseType,
                showAllThoughts: true,
                isLatest: entry.id == viewModel.agentOutputs.last?.id,
                charsPerSecond: 60,
                agentPosition: agentPosition(for: entry.agent, viewModel: viewModel)
              )
              .id(entry.id)
              .transition(reduceMotion ? .identity : .opacity)
            }
          }
          // Screen-level gutters (20pt horizontal / 8pt top) match the
          // reference HTML `.stream { padding: 8px 20px 16px }`. Intentional
          // literals — these are container-level, not per-bubble.
          .padding(.horizontal, 20)
          .padding(.top, 8)
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
    .background(Color.screenBackground.ignoresSafeArea())
    // PromoCard lives in the bottom safe area instead of a ZStack overlay:
    // that way the ScrollView's viewport shrinks to exclude the card's
    // footprint, so `scrollTo(lastId, anchor: .bottom)` lands the newest
    // message at the visible bottom — above the card, not hidden beneath
    // it. The previous `.padding(.bottom, 160)` approach reserved scroll
    // content space but did NOT shrink the viewport, so the anchor still
    // slid the last message under the overlay.
    .safeAreaInset(edge: .bottom, spacing: Spacing.l) {
      PromoCard(
        modelState: currentState,
        replayHadStarted: replayHadStarted,
        onRetry: { modelManager.startDownload(descriptor: descriptor) },
        onCancel: triggerCancelConfirmation)
    }
  }

  private func currentPresetName(viewModel: ReplayViewModel) -> String {
    guard case .playing(let sourceIndex, _) = viewModel.state,
      sourceIndex < sources.count
    else { return "" }
    return sources[sourceIndex].scenario.name
  }

  /// Agent's zero-based index in the currently-playing replay's agent
  /// list, used by ``AvatarSlot`` for position-priority avatar color
  /// assignment. Returns `nil` when no replay is active or the agent
  /// isn't in the current source's `agents` list; the row then falls
  /// back to the name-based avatar resolution.
  private func agentPosition(
    for agentName: String, viewModel: ReplayViewModel
  ) -> Int? {
    guard case .playing(let sourceIndex, _) = viewModel.state,
      sourceIndex < sources.count
    else { return nil }
    return sources[sourceIndex].scenario.personas.firstIndex(where: { $0.name == agentName })
  }

  private func currentPhaseLabel(viewModel: ReplayViewModel) -> String {
    guard let phase = viewModel.currentPhase else { return "" }
    let name = Self.phaseDisplayName(phase)
    if let round = viewModel.currentRound {
      return "\(name)ラウンド \(round)"
    }
    return name
  }

  /// Human-readable Japanese label for a phase type. Keeps `PhaseType` free
  /// of view-layer formatting concerns; final wording follows the copy pass
  /// per spec §2 decision 13.
  private static func phaseDisplayName(_ phase: PhaseType) -> String {
    switch phase {
    case .speakAll: return "発言"
    case .speakEach: return "個別発言"
    case .vote: return "投票"
    case .choose: return "選択"
    case .scoreCalc: return "スコア計算"
    case .assign: return "割当"
    case .eliminate: return "脱落"
    case .summarize: return "要約"
    case .conditional: return "条件分岐"
    }
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
    guard case .ready = newState else { return }
    if showsCompleteOverlay {
      // First-launch slot: trigger the in-content overlay; RootView's
      // own state observer takes the user to the `.ready` AppState.
      replayVM?.downloadComplete()
    } else {
      // Settings cover: dismiss immediately. The overlay's
      // "tap anywhere to begin" copy is meaningless here — the user
      // returns to the Settings list, not a fresh app session.
      onComplete?()
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

// `DLCompleteOverlay` lives in its own file so this one stays under
// swiftlint's 400-line cap. See `DLCompleteOverlay.swift`.

// MARK: - Previews

// The outer view exercises the default (`.checking` → fallback) path.
// `ModelManager.state` is `private(set)`, so richer variants would
// require a production seam; the `fallbackBranch` pure function is
// unit-tested instead (item 8).
#Preview {
  DemoReplayHostView(
    modelManager: ModelManager(),
    descriptor: ModelRegistry.gemma4E2B)
}
