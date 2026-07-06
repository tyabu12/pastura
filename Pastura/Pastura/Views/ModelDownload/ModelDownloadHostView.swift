import SwiftUI
import os

/// Host view for the DL-time demo replay feature. Owns the entire
/// `.needsModelDownload` UI surface — every per-`ModelState` rendering
/// branch (checking, unsupported device, Wi-Fi advisory, plain progress,
/// plain error, demo replay) is dispatched from
/// ``stateView(state:demosCount:replayHadStarted:requiresCellularConsent:)``
/// in `ModelDownloadHostView+StateFallbacks.swift` (#191 absorbed the
/// former `ModelDownloadView`).
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
/// - On first appearance, `.task { }` enumerates bundled demos via
///   `BundledDemoReplaySource.loadAll(...)`. If at least
///   `minPlayableDemoCount` demos validate, constructs a `ReplayViewModel`
///   and calls `start()`. No cellular check here — the cellular gate
///   moved upstream to `ModelManager.startDownload` (#191).
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
/// `initialLoad()` re-loads sources without leaking `replayHadStarted`
/// from the prior attempt.
struct ModelDownloadHostView: View {
  let modelManager: ModelManager
  let descriptor: ModelDescriptor
  let showsCompleteOverlay: Bool
  let onComplete: (() -> Void)?
  let onCancel: (() -> Void)?
  /// First-launch slot only: closure invoked when `ModelManager.state`
  /// reaches `.ready` AND any required overlay hand-off has completed.
  /// `RootView` uses this to drive `appState = .ready(deps)` *after*
  /// `DLCompleteOverlay` has been visible long enough to register —
  /// previously, `RootView` ran `finalizeInit` immediately on `.ready`
  /// and unmounted the overlay mid-fade (issue #202).
  /// Settings cover passes `nil` and uses `onComplete` instead.
  let onReady: ((String) -> Void)?

  init(
    modelManager: ModelManager,
    descriptor: ModelDescriptor,
    showsCompleteOverlay: Bool = true,
    onComplete: (() -> Void)? = nil,
    onCancel: (() -> Void)? = nil,
    onReady: ((String) -> Void)? = nil
  ) {
    self.modelManager = modelManager
    self.descriptor = descriptor
    self.showsCompleteOverlay = showsCompleteOverlay
    self.onComplete = onComplete
    self.onCancel = onCancel
    self.onReady = onReady
  }

  /// Minimum number of validated bundled demos required to render the
  /// demo host. Below this floor we render the plain progress fallback
  /// — the rotation loop is unsatisfying with a single demo (spec §5.2).
  static let minPlayableDemoCount = 2

  @Environment(\.scenePhase) private var scenePhase
  // Module-internal (not `private`) so the sibling `+ChatStream.swift`
  // extension can read it for the row `.transition` + scroll-follow
  // animation gating. `private` only reaches same-file extensions.
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  @State private var replayVM: ReplayViewModel?
  // Internal (not `private`) so `+ChatStream.swift`'s `promoCardInset`
  // can read it. Same rationale as `reduceMotion` above.
  @State var replayHadStarted: Bool = false
  // Internal (not `private`) so `+ChatStream.swift`'s `agentPosition`
  // / `promoCardInset` and `currentPresetName` can read it.
  @State var sources: [any ReplaySource] = []
  /// The persona shown when the viewer taps an agent's avatar / name in the
  /// demo stream (#942). Resolved from the active source's scenario via
  /// ``personaItem(for:viewModel:)`` — `nil` (no active source, or an
  /// unmatched name) simply doesn't present.
  @State var selectedPersona: PersonaSheetItem?
  // Type-once latch for opening cards (#867), keyed by `ChatItem.scenarioIntro`
  // id. Generalizes the live Sim's single reveal latch
  // (`SimulationViewModel.introRevealHasBegun`) to the demo's
  // many cards (one per rotated segment): the card lives in a `LazyVStack`, so
  // scrolling an already-typed card back into view must render it statically
  // (`charsPerSecond: nil`) instead of re-typing. Internal (not `private`) so
  // the sibling `+ChatStream.swift` extension can read/insert. Never cleared —
  // on `.loop` wrap `chatItems` is wiped and each re-shown card gets a fresh
  // UUID (so it re-reveals, intended), leaving only stale UUIDs here; the
  // ~16 B/entry growth over a download's lifetime is negligible.
  @State var typedIntroIds: Set<UUID> = []
  @State private var isShowingCancelConfirmation: Bool = false
  // Thought-visibility (`▸ THINKING` expanded) now lives on `ReplayViewModel`
  // (`showAllThoughts`) so the pacing floor can read it; the control bar binds
  // `$viewModel.showAllThoughts`. See the VM property's doc-comment.
  /// Re-entry guard for `handleModelStateChange`: `.onChange(of: currentState)`
  /// only fires on inequality, but a defensive same-value re-emit by
  /// `ModelManager` (or a future refactor) would otherwise dispatch the
  /// ready handoff twice. One-shot per host instance — re-mount (e.g.
  /// cover re-presentation) yields a fresh struct.
  @State private var didFireReady: Bool = false
  /// Captured `modelPath` from the `.ready` arrival, held while the
  /// overlay is awaiting the user's tap. Cleared when the tap fires
  /// `onReady?(modelPath)` and `RootView` swaps to `HomeView` (which
  /// unmounts this view anyway, so the cleanup is defensive).
  @State private var pendingReadyModelPath: String?

  /// Per-descriptor download state. Defaults to `.checking` if the entry is
  /// missing from the state dict (only expected pre-`checkModelStatus`).
  ///
  /// Module-internal (not `private`) so `+ChatStream.swift`'s
  /// `promoCardInset` can read it.
  var currentState: ModelState {
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
      .sheet(
        item: $selectedPersona,
        onDismiss: {
          // Unpark on ANY dismissal (swipe / tap-away / programmatic). Bound to
          // the sheet's lifecycle — not `.onChange(→false)` — so a stuck-true =
          // frozen demo playback can never outlive the sheet. #942 PR2.
          replayVM?.isPlaybackHeldForSheet = false
        },
        content: { item in
          PersonaDetailSheet(persona: item.persona, position: item.position)
        }
      )
      .onChange(of: selectedPersona != nil) { _, isPresented in
        // Park demo playback only on present; the unpark is the sheet's
        // `onDismiss` above. Gating on the *presented* transition (not the tap)
        // makes a persona-not-found tap — which leaves `selectedPersona` nil and
        // never shows a sheet — a no-op instead of a frozen demo with no sheet.
        if isPresented { replayVM?.isPlaybackHeldForSheet = true }
      }
  }

  /// Closure handed to the children that own the visible cancel
  /// affordance (`PromoCard` in the demo branch, the plain-progress
  /// fallback in `+StateFallbacks.swift`). Returns `nil` when the
  /// caller did not wire `onCancel`, which lets the children hide
  /// their cancel UI — the first-launch slot relies on this to stay
  /// uncancellable. Tapping the affordance flips a `@State` flag here
  /// so the host owns the confirmation dialog; the destructive action
  /// eventually fires `onCancel?()` from inside that dialog.
  ///
  /// Module-internal (drops `private`) so the sibling
  /// `+StateFallbacks.swift` extension can read it.
  var triggerCancelConfirmation: (() -> Void)? {
    guard onCancel != nil else { return nil }
    return { isShowingCancelConfirmation = true }
  }

  @ViewBuilder
  private var currentView: some View {
    switch Self.stateView(
      state: currentState,
      demosCount: sources.count,
      replayHadStarted: replayHadStarted,
      requiresCellularConsent: modelManager.requiresCellularConsent
    ) {
    case .checking:
      checkingFallback
    case .unsupportedDevice:
      unsupportedDeviceFallback
    case .wifiRequired:
      wifiRequiredFallback
    case .notDownloadedDefensive:
      notDownloadedDefensiveFallback
    case .plainProgress:
      let progress: Double = {
        if case .downloading(let value) = currentState { return value }
        return 0
      }()
      plainProgressFallback(progress: progress)
    case .error(let message):
      plainErrorFallback(message: message)
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
            DLCompleteOverlay(onTap: handleOverlayTap)
          }
        }
    } else {
      // Until `.task { }` finishes loading sources, render an empty
      // background. The `stateView` dispatch routes away from the demo
      // host before this nil state is reached once `sources` updates.
      Color.screenBackground.ignoresSafeArea()
    }
  }

  /// Fires when the user taps the overlay. Forwards the captured
  /// `modelPath` to the `onReady` callback and clears the pending
  /// state. Defensive: only fires if `pendingReadyModelPath` is set,
  /// which it should be whenever `viewModel.state == .transitioning`
  /// (set in `handleModelStateChange` before `downloadComplete()` is
  /// called).
  private func handleOverlayTap() {
    guard let modelPath = pendingReadyModelPath else { return }
    pendingReadyModelPath = nil
    onReady?(modelPath)
  }

  // Module-internal so the sibling `+GameHeader.swift` extension can
  // call this helper. `private` only reaches same-file extensions.
  func currentPresetName(viewModel: ReplayViewModel) -> String {
    guard let sourceIndex = viewModel.currentSourceIndex,
      sourceIndex < sources.count
    else { return "" }
    return sources[sourceIndex].scenario.name
  }

  // MARK: - Lifecycle

  // Cellular gate moved upstream to `ModelManager.startDownload` (#191), so
  // `initialLoad` no longer runs a 1-shot `NWPathMonitor` check — it just
  // loads bundled demos. The `stateView` dispatcher handles routing.
  private func initialLoad() async {
    Self.logger.notice("initialLoad: starting (descriptor=\(descriptor.id, privacy: .public))")
    // Randomize the demo order on each load so the looped rotation
    // isn't a fixed sequence (advanceAfterSource wraps via `% sources.count`,
    // preserving whatever order this array holds). Shuffle exactly ONCE into
    // the shared `loaded` binding — `sources` and the VM's copy must agree
    // on order because `currentPresetName(viewModel:)` resolves the header
    // name via `sources[viewModel.currentSourceIndex]`; two separate
    // `.shuffled()` calls would desync them. `loadAll()` itself stays
    // deterministic so order-sensitive tests keep passing.
    let loaded = BundledDemoReplaySource.loadAll().shuffled()
    Self.logger.notice(
      "initialLoad: loaded \(loaded.count, privacy: .public) sources")
    sources = loaded
    guard loaded.count >= Self.minPlayableDemoCount else {
      Self.logger.notice(
        "initialLoad: sources count \(loaded.count, privacy: .public) below floor \(Self.minPlayableDemoCount, privacy: .public) — stateView will route to plainProgress"
      )
      return
    }

    let viewModel = ReplayViewModel(sources: loaded)
    replayVM = viewModel
    viewModel.start()
    replayHadStarted = true
    Self.logger.notice("initialLoad: replayVM started — demo host body should render")
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
    guard case .ready(let modelPath) = newState else { return }
    guard !didFireReady else { return }
    didFireReady = true

    switch Self.readyDispatch(
      showsCompleteOverlay: showsCompleteOverlay,
      hasReplayVM: replayVM != nil) {
    case .fireOnComplete:
      // Settings cover: dismiss immediately. The overlay's
      // "Tap anywhere to begin" copy is meaningless here — the user
      // returns to the Settings list, not a fresh app session.
      onComplete?()
    case .fireOnReady(let awaitsTap) where awaitsTap:
      // First-launch slot, overlay path: flip the VM into `.transitioning`
      // so the overlay renders, then wait for the user to tap. The tap
      // handler (`handleOverlayTap`) reads back `pendingReadyModelPath`
      // and fires `onReady`. No timer — the user explicitly acknowledges
      // setup completion before transitioning to `HomeView`.
      pendingReadyModelPath = modelPath
      replayVM?.downloadComplete()
    case .fireOnReady:
      // First-launch slot, no-overlay path (sub-floor demo count or VM
      // failed to construct): there's nothing to render, so skip the
      // tap-acknowledgment and forward `.ready` immediately. Without
      // this branch, the user would be stuck on the plain progress
      // fallback with no overlay to tap.
      onReady?(modelPath)
    }
  }

}

// `DLCompleteOverlay`, the chat-stream rendering, the per-state UI
// helpers, and the pure routing functions live in their own files so this
// one stays under swiftlint's 400-line cap. See `DLCompleteOverlay.swift`,
// `ModelDownloadHostView+ChatStream.swift`,
// `ModelDownloadHostView+StateFallbacks.swift`, and
// `ModelDownloadHostView+Routing.swift`.

// MARK: - Previews

// The outer view exercises the default (`.checking` → fallback) path.
// `ModelManager.state` is `private(set)`, so richer variants would
// require a production seam; the `fallbackBranch` pure function is
// unit-tested instead (item 8).
#Preview {
  ModelDownloadHostView(
    modelManager: ModelManager(),
    descriptor: ModelRegistry.gemma4E2B)
}
