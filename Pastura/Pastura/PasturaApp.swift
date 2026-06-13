// swiftlint:disable file_length
// Deliberately long: RootView owns the full app-lifecycle state machine
// (initializing / needsModelSelection / needsModelDownload / ready /
// error), the Deep Link gate, and the toast overlay — projecting its
// state across three synced enums (`AppState` / `AppStateKind` /
// `DeepLinkBlockReason`). Splitting would require exporting these
// file-private enums across multiple files and widens an
// intentionally-small testable surface.
import SwiftUI

@main
struct PasturaApp: App {
  // PR2: required to receive `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
  // — SwiftUI's `App` protocol doesn't surface this UIKit callback. The
  // adaptor instantiates `PasturaAppDelegate` exactly once per process and
  // routes the system callback to it.
  @UIApplicationDelegateAdaptor(PasturaAppDelegate.self) private var appDelegate

  var body: some Scene {
    // RootView lives inside WindowGroup so each scene (iPad multi-window,
    // iPhone single window) gets its own @State — including its own
    // AppRouter / NavigationStack path. App-struct-level @State would be
    // shared across all scenes. Deep Link state (`DeepLinkGate`, pending
    // URL, last-deep-linked id) is likewise per-scene so iOS routing a
    // `pastura://` URL to the active scene doesn't leak into others.
    WindowGroup {
      RootView()
    }
  }
}

/// Top-level app navigation state.
///
/// File-private to RootView; nothing outside this file looks at the raw
/// lifecycle, so the smaller surface keeps the public API tidy.
private enum AppState {
  /// App is initializing (checking model, setting up database).
  case initializing
  /// First-launch on a multi-model device: no active id persisted yet and
  /// every catalog descriptor resolves to `.notDownloaded`. The UI shows
  /// the model picker; tapping a row calls `setActiveModel` and
  /// transitions to `.needsModelDownload`.
  case needsModelSelection
  /// Model needs to be downloaded before the app can run.
  case needsModelDownload
  /// App is ready — dependencies are initialized.
  case ready(AppDependencies)
  /// A fatal initialization error occurred.
  case error(String)
}

/// Equatable projection of `AppState` for use with `.onChange` — the
/// underlying enum carries an `AppDependencies` reference which is not
/// meaningfully Equatable and whose identity we don't want to compare on.
private enum AppStateKind: Equatable {
  case initializing
  case needsModelSelection
  case needsModelDownload
  case ready
  case error
}

/// Reason a Deep Link is queued rather than routed immediately. Drives
/// the toast message shown while the URL is pending.
private enum DeepLinkBlockReason: Equatable {
  case initializing
  case modelSelection
  case modelDownload
  case error
  case sheetPresented
  case simulationActive

  var toastText: String {
    switch self {
    case .initializing:
      return String(localized: "Opening shared scenario after setup…")
    case .modelSelection:
      return String(localized: "Will open after you choose a model")
    case .modelDownload:
      return String(localized: "Will open once the model finishes downloading")
    case .error:
      return String(localized: "Will open after retrying setup")
    case .sheetPresented:
      return String(localized: "Close this sheet to open the shared scenario")
    case .simulationActive:
      return String(localized: "Will open when you exit this simulation")
    }
  }
}

/// Identifiable error payload for the root-level Deep Link alert.
private struct DeepLinkErrorAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

// swiftlint:disable type_body_length
// Same justification as the file-level `file_length` disable above:
// helpers already split into a same-file extension below; remaining
// body still nudges over 250 because the deep-link gate logic added
// in #191 lives next to the state-machine `body` it gates.
/// Per-scene root view. Owns the model-download state machine, the
/// dependency container, the `AppRouter` that drives the root
/// `NavigationStack`'s path, and the Deep Link coordination state.
private struct RootView: View {
  @State private var appState: AppState = .initializing
  @State private var modelManager = ModelManager()
  @State private var router = AppRouter()
  @State private var gate = DeepLinkGate()
  @State private var lastDeepLinkedScenarioId: String?
  @State private var deepLinkError: DeepLinkErrorAlert?

  // Launch animation state — see `Pastura/Pastura/Views/Splash/`.
  // `splashKind` defaults to `.cold` (process-fresh = cold launch) except
  // in UI-test mode where 1.6 s of splash would slow every test for no
  // navigation-regression value.
  @State private var coordinator = LaunchPhaseCoordinator()
  @State private var splashKind: LaunchKind? = {
    #if DEBUG
      // Capture-tooling overrides (scripts/motion-capture.sh): force a
      // specific splash to play for animation recording even under
      // `--ui-test`, which otherwise suppresses it. DEBUG-only and
      // checked before `--ui-test` so the recorder can seed Home fixtures
      // (via `--ui-test`) while still playing the splash over them. Absent
      // these args, control falls through unchanged.
      if CommandLine.arguments.contains("--capture-launch-warm") { return .warm }
      if CommandLine.arguments.contains("--capture-launch") { return .cold }
      if CommandLine.arguments.contains("--ui-test") { return nil }
    #endif
    return .cold
  }()
  @Environment(\.scenePhase) private var scenePhase

  /// Maximum extra hold the cold splash allows past `coldDuration` while
  /// init is still resolving. Past this cap the splash dismisses and the
  /// underlying `.initializing` ProgressView takes over.
  private static let coldSplashMaxExtension: TimeInterval = 1.0

  var body: some View {
    ZStack {
      mainContent
      deepLinkToast
      splashOverlay  // z-order above mainContent AND toast per critic axis 7
    }
    .onOpenURL { handleOpenURL($0) }
    // Drain triggers: fire whenever any signal that gates navigability
    // changes. `tryDrain` itself re-checks all preconditions, so spurious
    // triggers are cheap.
    .onChange(of: appStateKind) { _, _ in tryDrain() }
    .onChange(of: gate.sheetPresentationCount) { _, _ in tryDrain() }
    .onChange(of: router.path) { _, _ in tryDrain() }
    .onChange(of: gate.pendingURL) { _, new in if new != nil { tryDrain() } }
    .onChange(of: scenePhase) { old, new in handleScenePhase(from: old, to: new) }
    // Reset source-attribution when the user pops all the way back. Any
    // subsequent visit to the same gallery scenario detail (via Share
    // Board, for instance) should not show the "Opened from external
    // link" banner.
    .onChange(of: router.path.isEmpty) { _, isEmpty in
      if isEmpty { lastDeepLinkedScenarioId = nil }
    }
    .alert(item: $deepLinkError) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .modifier(CellularConsentDialogModifier(modelManager: modelManager))
    // Inject the gate at the body root so `.deepLinkGated()` markers
    // mounted inside `mainContent` (e.g. the cellular consent dialog
    // marker, which fires on `.needsModelDownload`, well before
    // `.ready`) and inside `CellularConsentDialogModifier`'s own body
    // both resolve to the real gate instance. The downstream
    // `.environment(gate)` on `HomeView` becomes redundant but is
    // kept until a follow-up cleanup to minimise blast radius.
    .environment(gate)
  }

  // MARK: - Content

  @ViewBuilder
  private var mainContent: some View {
    Group {
      switch appState {
      case .initializing:
        ProgressView(String(localized: "Initializing..."))
          .task {
            await initialize()
          }

      case .needsModelSelection:
        ModelPickerView(modelManager: modelManager, onSelect: handleModelPick)

      case .needsModelDownload:
        // The `if let` is defensive — `.needsModelDownload` is only
        // reached after `activeDescriptor` has been resolved (see
        // `initialize()`), so production never falls through.
        if let descriptor = modelManager.activeDescriptor {
          // `onReady` (not a sibling `.onChange(of: activeState)`) drives
          // `finalizeInit` so the host view can hold the overlay visible
          // for its fade duration before `RootView` swaps in `HomeView`.
          // See ADR-007 §3.3 (d) and `ModelDownloadHostView.readyDispatch`.
          ModelDownloadHostView(
            modelManager: modelManager,
            descriptor: descriptor,
            onReady: { modelPath in
              Task { await finalizeInit(modelPath: modelPath) }
            })
        } else {
          Color.clear
        }

      case .ready(let dependencies):
        HomeView()
          .environment(dependencies)
          .environment(router)
          .environment(gate)
          // `ModelManager` is exposed so Settings → Models can observe
          // state and drive switch / download / delete without threading
          // it through every intermediate view.
          .environment(modelManager)
          .environment(\.lastDeepLinkedScenarioId, lastDeepLinkedScenarioId)

      case .error(let message):
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(Color.danger)
          Text(String(localized: "Initialization Failed"))
            .font(.headline)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button(String(localized: "Retry")) {
            appState = .initializing
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
      }
    }
  }

  @ViewBuilder
  private var deepLinkToast: some View {
    // Sheet-presented case: iOS presents sheets in their own presentation
    // context so this overlay is visually occluded — acceptable because
    // the user dismisses the sheet and the drain fires immediately.
    // Init / modelDownload / error / simulation-active cases render over
    // the RootView's content and are visible.
    //
    // Splash-presented case (cold or warm): suppress so the toast doesn't
    // render invisibly under the splash with the next state's text. Per
    // critic axis 7 — splash z-orders above the toast, and the existing
    // `.initializing` block in `tryDrain` already prevents drain during
    // cold launch, so suppressing the toast here is purely visual.
    if gate.pendingURL != nil, let reason = deepLinkBlockReason, splashKind == nil {
      VStack {
        Spacer()
        Text(reason.toastText)
          .font(.footnote)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(.thinMaterial, in: Capsule())
          .shadow(radius: 4, y: 2)
          .padding(.bottom, 32)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .animation(.easeInOut(duration: 0.2), value: reason)
      .allowsHitTesting(false)
    }
  }

  // MARK: - Splash overlay

  @ViewBuilder
  private var splashOverlay: some View {
    if let kind = splashKind {
      Group {
        switch kind {
        case .cold:
          ColdSplashView()
            .transition(.coldSplashExit)
            .task { await runColdSplashTimeline() }
        case .warm:
          WarmSplashView()
            .transition(.warmSplashExit)
            .task { await runWarmSplashTimeline() }
        }
      }
      .zIndex(1)
    }
  }

  // MARK: - Deep Link coordination

  private var appStateKind: AppStateKind {
    switch appState {
    case .initializing: return .initializing
    case .needsModelSelection: return .needsModelSelection
    case .needsModelDownload: return .needsModelDownload
    case .ready: return .ready
    case .error: return .error
    }
  }

  private var deepLinkBlockReason: DeepLinkBlockReason? {
    switch appState {
    case .initializing: return .initializing
    case .needsModelSelection: return .modelSelection
    case .needsModelDownload: return .modelDownload
    case .error: return .error
    case .ready:
      if gate.isSheetActive { return .sheetPresented }
      if isSimulationOnTop { return .simulationActive }
      return nil
    }
  }

  private var isSimulationOnTop: Bool {
    if case .some(.simulation) = router.path.last { return true }
    return false
  }

  private func handleOpenURL(_ url: URL) {
    guard DeepLinkURL.parse(url) != nil else {
      deepLinkError = DeepLinkErrorAlert(
        title: String(localized: "Unsupported Link"),
        message: String(localized: "This link doesn't match Pastura's expected format.")
      )
      return
    }
    // Most-recent-wins: a newer URL replaces any older pending one.
    gate.pendingURL = url
    // Call drain synchronously as well so a drainable URL clears before
    // the toast would render. `.onChange` would pick it up otherwise,
    // but with a one-frame flash during state propagation.
    tryDrain()
  }

  private func tryDrain() {
    guard let url = gate.pendingURL else { return }
    guard case .ready(let deps) = appState else { return }
    guard !gate.isSheetActive else { return }
    guard !isSimulationOnTop else { return }
    guard let parsed = DeepLinkURL.parse(url) else {
      gate.pendingURL = nil
      return
    }
    // Clear before the async work so the pendingURL `.onChange` doesn't
    // refire the drain for the same URL. A URL arriving during the
    // resolve will replace this cleared slot and be picked up after.
    gate.pendingURL = nil

    Task { @MainActor in
      let resolver = DeepLinkResolver(galleryService: deps.galleryService)
      switch parsed {
      case .scenario(let id):
        let result = await resolver.resolve(id: id)
        applyResolution(result, requestedId: id)
      }
    }
  }

  private func applyResolution(_ result: DeepLinkResolution, requestedId: String) {
    switch result {
    case .found(let scenario):
      lastDeepLinkedScenarioId = scenario.id
      router.push(.galleryScenarioDetail(scenario: scenario))
    case .notFound:
      deepLinkError = DeepLinkErrorAlert(
        title: String(localized: "Scenario Not Found"),
        message: String(
          localized: "This scenario isn't in the gallery anymore.")
      )
    case .networkAndCacheMiss:
      deepLinkError = DeepLinkErrorAlert(
        title: String(localized: "Could Not Reach Gallery"),
        message: String(localized: "Check your connection and try again.")
      )
    case .corruptedCache:
      deepLinkError = DeepLinkErrorAlert(
        title: String(localized: "Gallery Cache Corrupted"),
        message: String(
          localized: "Open Shared Scenarios to refresh, then try the link again.")
      )
    }
  }

  // MARK: - Lifecycle

  private func initialize() async {
    #if DEBUG
      if CommandLine.arguments.contains("--ui-test") {
        await setupUITestState()
        return
      }
    #endif
    // Fail-fast on catalog collisions at the earliest possible point so
    // duplicate ids / fileNames crash in dev rather than corrupting
    // ModelManager.state lookups or filesystem paths silently at runtime.
    ModelRegistry.validateNoCollisions()
    #if targetEnvironment(simulator)
      // On simulator, use OllamaService directly — no model download needed.
      do {
        let deps = try AppDependencies.production()
        // Register BG task handler early so iOS 26+ can launch us in background.
        // Must be called before the first scene activates.
        deps.backgroundManager.register()
        PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)
        appState = .ready(deps)
      } catch {
        appState = .error(
          String(
            format: String(localized: "Database error: %@"), error.localizedDescription))
      }
    #else
      // PR2 cross-launch reattach. Order is load-bearing:
      //   1. `waitForNetworkPathReady` warms `NetworkPathMonitor` so the
      //      cellular gate inside `attachToInFlightDownloads` reads the
      //      actual path (not the launch-time default of `false`). On real
      //      devices, a relaunch on cellular without consent races this
      //      callback — awaiting here closes the race.
      //   2. `checkModelStatus` runs BEFORE attach so any `.error` set by
      //      `finalizeReattachedDownload` (SHA mismatch on a reattached DL)
      //      cannot be overwritten by `computeState`'s `.notDownloaded`
      //      filesystem fallback.
      //   3. `attachToInFlightDownloads` observes any BG tasks that
      //      `nsurlsessiond` carried over from a prior process generation
      //      (including ones the OS-relaunch path delivered for completion)
      //      and transitions matched descriptors to `.downloading`. Replaces
      //      PR1's heavy-handed `cleanupOrphanBackgroundTasks` cancel-all.
      await modelManager.waitForNetworkPathReady()
      modelManager.checkModelStatus()
      await modelManager.attachToInFlightDownloads()
      // Fresh-install multi-model gate — returning users (persisted id)
      // or single-model catalogs bypass the picker. See
      // `ModelManager.shouldShowInitialModelPicker` for the precise
      // condition.
      if modelManager.shouldShowInitialModelPicker {
        appState = .needsModelSelection
        return
      }
      switch modelManager.activeState {
      case .ready(let modelPath):
        await finalizeInit(modelPath: modelPath)
      case .notDownloaded:
        // Auto-resume: user has already opted in (active id was persisted
        // by a prior picker tap or by single-model catalog default), so
        // the only reason we'd be in `.notDownloaded` here is that the
        // download wasn't completed AND `attachToInFlightDownloads` didn't
        // find an OS-attached BG task for this descriptor — either the app
        // was killed before the BG session even started, or the OS reaped
        // the task pre-launch. Start a fresh `startDownload` so the user
        // lands directly on the demo host body / progress fallback (or, on
        // cellular without consent, the Wi-Fi advisory + scene-level
        // confirmation dialog — #191).
        //
        // Reaching this branch implies attach did NOT transition this
        // descriptor to `.downloading`, so no double-`startDownload` race
        // is possible (the overlap-safety invariant — PR2 critic axis 5).
        if let descriptor = modelManager.activeDescriptor {
          modelManager.startDownload(descriptor: descriptor)
        }
        appState = .needsModelDownload
      case .downloading:
        // PR2 reattach path active for the active descriptor — observer
        // Task is updating progress; ModelDownloadView observes the same
        // state and shows the in-flight progress UI.
        appState = .needsModelDownload
      case .unsupportedDevice, .error:
        appState = .needsModelDownload
      case .checking:
        // Should not happen after synchronous checkModelStatus, but handle gracefully
        appState = .needsModelDownload
      }
    #endif
  }

  private func finalizeInit(modelPath: String) async {
    // `activeDescriptor` is guaranteed non-nil by `ModelManager.resolveInitialActiveID`
    // (it always returns a catalog id when the catalog is non-empty, and
    // `ModelRegistry.validateNoCollisions()` in `initialize()` rejects an empty
    // production catalog upstream). Surface a fatal error rather than silently
    // falling back to hardcoded Gemma values so future regressions in the
    // catalog wiring fail loudly.
    guard let descriptor = modelManager.activeDescriptor else {
      appState = .error(String(localized: "No active model descriptor resolvable from catalog"))
      return
    }
    do {
      let llm = LlamaCppService(
        modelPath: modelPath,
        stopSequence: descriptor.stopSequence,
        modelIdentifier: descriptor.displayName,
        systemPromptSuffix: descriptor.systemPromptSuffix,
        assistantPrefix: descriptor.assistantPrefix
      )
      let deps = try AppDependencies.production(llmService: llm)
      // Register BG task handler early so iOS 26+ can launch us in background.
      deps.backgroundManager.register()
      PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)
      appState = .ready(deps)
    } catch {
      appState = .error(
        String(
          format: String(localized: "Database error: %@"), error.localizedDescription))
    }
  }

  #if DEBUG
    /// UI-test-only bootstrap: constructs an in-memory `AppDependencies` with a
    /// deterministic `MockLLMService` and `StubGalleryService`, skips preset
    /// loading, and transitions directly to `.ready`. Avoids network, disk
    /// persistence, and the real LLM — all of which introduce non-determinism
    /// that would make navigation regressions hard to catch reliably.
    private func setupUITestState() async {
      do {
        let llm = MockLLMService(responses: [])
        let gallery = StubGalleryService.uiTestPreset()
        let editorSeedYAML =
          CommandLine.arguments.contains("--ui-test-editor-seed-yaml")
          ? StubScenarioSeeder.editorSeedYAML : nil
        let deps = try AppDependencies.inMemory(
          llmService: llm,
          galleryService: gallery,
          uiTestEditorSeedYAML: editorSeedYAML
        )
        try await StubScenarioSeeder.seed(into: deps.scenarioRepository)
        // Past Results fixtures are opt-in so plain --ui-test runs keep
        // exercising the empty state (ScreenshotTourTests opts in).
        if CommandLine.arguments.contains("--ui-test-seed-results") {
          try await StubResultSeeder.seed(
            simulationRepository: deps.simulationRepository,
            turnRepository: deps.turnRepository)
        }
        appState = .ready(deps)
      } catch {
        appState = .error("UI test setup failed: \(error.localizedDescription)")
      }
    }
  #endif
}
// swiftlint:enable type_body_length

// Helpers in an extension so they don't count against `RootView`'s
// `type_body_length` budget. Same-file extension on a `private` type is
// fine (private = file-scoped, extensions in the same file see private
// members).
extension RootView {

  /// Picker → AppState transition. Persists the chosen model and starts
  /// its download synchronously in the same frame as the AppState flip,
  /// so `ModelDownloadHostView` mounts with `currentState == .downloading`
  /// and routes directly to the demo host body. On cellular without
  /// consent the gate inside `ModelManager.startDownload` keeps the
  /// state at `.notDownloaded` and sets `pendingCellularConsent`; the
  /// scene-level `.confirmationDialog` (see `CellularConsentDialogModifier`)
  /// presents and `acceptCellularConsent` re-fires the download. The
  /// picker's "Start with this model" CTA is itself the user-action
  /// consent for the AppState flip.
  fileprivate func handleModelPick(_ pickedID: ModelID) {
    modelManager.setActiveModel(pickedID)
    if let descriptor = modelManager.activeDescriptor {
      modelManager.startDownload(descriptor: descriptor)
    }
    appState = .needsModelDownload
  }

  // MARK: - Splash timelines & scenePhase

  /// Cold splash dismissal: hold for `coldDuration`, optionally extend up
  /// to `coldSplashMaxExtension` while init is still resolving, then play
  /// the `.coldSplashExit` transition.
  ///
  /// Built on top of ``LaunchSplashTimer``: the timer encapsulates the
  /// min-time + extension contract (with unit-test coverage of the four
  /// resolution regimes), this function turns that into an observation
  /// loop because a SwiftUI view's `appStateKind` is a moving target that
  /// `LaunchSplashTimer.dismissalTime(...)` can't observe directly.
  ///
  /// `hardDeadline` from the timer drives the loop's upper bound so the
  /// two definitions of "how long can extension last" stay locked.
  fileprivate func runColdSplashTimeline() async {
    let timer = LaunchSplashTimer(
      minDuration: LaunchAnimationConfig.coldDuration,
      maxExtension: Self.coldSplashMaxExtension
    )
    try? await Task.sleep(nanoseconds: UInt64(timer.minDuration * 1_000_000_000))

    // Extension wait — poll up to `maxExtension`. 50 ms polling is
    // invisible to the user (well under one perceived frame at 60 Hz) and
    // bounded — at most 20 iterations for a 1-second cap.
    let maxExtensionMs: UInt64 = UInt64(timer.maxExtension * 1000)
    let pollIntervalMs: UInt64 = 50
    var elapsedMs: UInt64 = 0
    while appStateKind == .initializing && elapsedMs < maxExtensionMs {
      try? await Task.sleep(nanoseconds: pollIntervalMs * 1_000_000)
      elapsedMs += pollIntervalMs
    }

    // The exit's animation duration is the "72→100% of timeline" portion
    // of the original design — 28% × 1.6 s ≈ 448 ms. easeStandard matches
    // the README's fade-out curve cubic-bezier(.4, 0, .2, 1).
    let exitDuration = LaunchAnimationConfig.coldDuration * 0.28
    withAnimation(LaunchAnimationConfig.easeStandard(duration: exitDuration)) {
      splashKind = nil
    }
  }

  /// Warm splash dismissal: hold for `warmDuration`, then play the
  /// `.warmSplashExit` transition. Clears `lastBackgroundedAt` so a
  /// subsequent in-process toggle (foreground → background → foreground
  /// again within the threshold) picks up a fresh measurement window.
  fileprivate func runWarmSplashTimeline() async {
    let total = LaunchAnimationConfig.warmDuration
    // Hold through segments 1-3 (appear / inhale / exhale = 72%). The
    // remaining 28% is the parent's `.warmSplashExit` transition.
    let holdDuration = total * 0.72
    try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))

    let exitDuration = total * 0.28
    withAnimation(LaunchAnimationConfig.easeStandard(duration: exitDuration)) {
      splashKind = nil
    }
    coordinator.clearBackgrounded()
  }

  /// `scenePhase` observer driving the warm-launch decision and the
  /// background timestamp.
  ///
  /// Background-recording fires on transition into `.background` only —
  /// `.inactive` is a transient state (Control Center, incoming call, app
  /// switcher dismiss) that should not reset the warm threshold.
  ///
  /// Warm-splash gating uses the pure
  /// ``LaunchPhaseCoordinator/shouldPlayWarmSplash(launchKind:appIsReady:isSimulationOnTop:isSheetActive:)``
  /// predicate so the suppression matrix stays unit-tested
  /// (`LaunchPhaseCoordinatorTests`).
  fileprivate func handleScenePhase(from old: ScenePhase, to new: ScenePhase) {
    if new == .background {
      coordinator.recordBackgrounded()
      return
    }
    guard new == .active, old == .background else { return }
    // Don't restart a splash that's already on screen (rapid bg/fg toggle
    // mid-cold-launch). The cold splash owns its own dismissal timeline.
    guard splashKind == nil else { return }
    let kind = LaunchPhaseCoordinator.nextLaunchKind(
      now: .now,
      lastBackgroundedAt: coordinator.lastBackgroundedAt,
      threshold: LaunchAnimationConfig.warmThreshold
    )
    let shouldPlay = LaunchPhaseCoordinator.shouldPlayWarmSplash(
      launchKind: kind,
      appIsReady: appStateKind == .ready,
      isSimulationOnTop: isSimulationOnTop,
      isSheetActive: gate.isSheetActive
    )
    guard shouldPlay else {
      // Warm-eligible by elapsed but suppressed by app state — clear the
      // bg timestamp so a subsequent return after the user finishes their
      // simulation / sheet doesn't mistakenly trigger warm splash.
      if kind == .warm { coordinator.clearBackgrounded() }
      return
    }
    withAnimation(LaunchAnimationConfig.easeStandard(duration: 0.15)) {
      splashKind = .warm
    }
  }
}

/// Scene-level cellular consent confirmation dialog (#191 / ADR-007
/// §3.3 (c)). Lives at file scope as a `ViewModifier` rather than
/// inline inside `RootView.body` to keep the `RootView` struct under
/// swiftlint's `type_body_length` cap.
///
/// Picker / relaunch auto-resume / Settings cover all converge on
/// `ModelManager.startDownload`, which sets `pendingCellularConsent`
/// when the cellular gate fires. This single dialog observes that
/// state regardless of who triggered the call.
///
/// Tap-outside-to-dismiss is wired through the `set` closure of the
/// synthesized `Binding<Bool>` so it counts as decline — without that,
/// the gate would silently leave `pendingCellularConsent` non-nil
/// after the dialog closed itself.
///
/// Deep links arriving while the dialog is visible are gated through
/// `DeepLinkGate.sheetPresentationCount` via a hidden
/// `Color.clear.deepLinkGated()` marker that mounts only while
/// `pendingCellularConsent != nil`. This reuses the same
/// onAppear/onDisappear ±1 path as sheets/covers; we deliberately
/// avoid an `onChange(of: pendingCellularConsent?.id)` path because
/// `acceptCellularConsent` clears and re-requires the descriptor
/// within a single frame on edge cases (consent-store write failure,
/// test stubs returning false), and SwiftUI's Equatable coalescing
/// can drop one side of the nil↔id transition pair, leaking the
/// counter in the +1 direction and stalling the gate forever.
private struct CellularConsentDialogModifier: ViewModifier {
  let modelManager: ModelManager

  func body(content: Content) -> some View {
    content
      .background {
        if modelManager.pendingCellularConsent != nil {
          Color.clear.deepLinkGated()
        }
      }
      .confirmationDialog(
        String(localized: "Download on cellular?"),
        isPresented: Binding(
          get: { modelManager.pendingCellularConsent != nil },
          set: { newValue in
            if !newValue, modelManager.pendingCellularConsent != nil {
              modelManager.declineCellularConsent()
            }
          }),
        titleVisibility: .visible,
        presenting: modelManager.pendingCellularConsent
      ) { _ in
        Button(String(localized: "Download anyway"), role: .destructive) {
          modelManager.acceptCellularConsent()
        }
        Button(String(localized: "Wait for Wi-Fi"), role: .cancel) {
          modelManager.declineCellularConsent()
        }
      } message: { descriptor in
        Text(
          String(
            localized:
              "Downloading \(ModelSettingsRow.formattedFileSize(descriptor.fileSize)) on cellular may use significant data. Wi-Fi is recommended."
          ))
      }
  }
}
