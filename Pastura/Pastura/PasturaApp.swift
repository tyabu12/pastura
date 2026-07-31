// swiftlint:disable file_length
// Deliberately long: RootView owns the full app-lifecycle state machine
// (initializing / needsModelSelection / needsModelDownload / ready /
// error), the Deep Link gate, and the toast overlay — projecting its
// state across three synced enums (`AppState` / `AppStateKind` /
// `DeepLinkBlockReason`). Splitting would require exporting these
// file-private enums across multiple files and widens an
// intentionally-small testable surface.
import OSLog
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
  /// A recoverable database failure (deterministic migration failure, #546).
  /// Carries the underlying error description. A plain retry would re-fail,
  /// so the UI offers a consent-gated reset that backs up and recreates the
  /// DB — distinct from `.error`, whose Retry is the right affordance for
  /// transient failures.
  case databaseRecovery(String)
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
  case databaseRecovery
  case error
}

/// Reason a Deep Link is queued rather than routed immediately. Drives
/// the toast message shown while the URL is pending.
private enum DeepLinkBlockReason: Equatable {
  case initializing
  case modelSelection
  case modelDownload
  case databaseRecovery
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
    case .databaseRecovery:
      return String(localized: "Will open after database recovery")
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
  // Four per-tab AppRouters + selectedTab (ADR-016 D3). Replaces the
  // single root `AppRouter` — the bottom-tab IA has one stack per tab.
  // Named `tabCoordinator` to avoid colliding with the splash
  // `coordinator` (LaunchPhaseCoordinator) below.
  @State private var tabCoordinator = TabCoordinator()
  @State private var gate = DeepLinkGate()
  @State private var lastDeepLinkedScenarioId: String?
  @State private var deepLinkError: DeepLinkErrorAlert?

  /// Captures the active model path when a recoverable DB failure is hit on
  /// device, so `recoverDatabase()` can rebuild the `LlamaCppService` after
  /// the reset. `nil` signals the simulator path (no on-device LLM). See
  /// `databaseRecovery` AppState (#546).
  @State private var pendingRecoveryModelPath: String?

  /// Drives the `.databaseRecovery` "Report this problem" sheet (#580),
  /// which pre-fills the migration error into the report surfaces.
  @State private var isRecoveryReportSheetPresented: Bool = false

  private static let logger = Logger(subsystem: "app.pastura.Pastura", category: "AppInit")

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
      // The `demo` capture variant records the demo replay screen, not the
      // splash — suppress the splash so it doesn't clip the recording window.
      if CommandLine.arguments.contains("--capture-demo") { return nil }
      if CommandLine.arguments.contains("--ui-test") { return nil }
    #endif
    return .cold
  }()
  #if DEBUG
    // Store-screenshot capture only (`scripts/store-shots.sh` /
    // `StoreScreenshotTests`): `--ui-test-open-scoreboard` presents
    // `ScoreboardSheet` with fixed sample data so the scoreboard — otherwise
    // reachable only from a completed live run — can be captured
    // deterministically. Everything below (state + `.sheet`) is `#if DEBUG`
    // so Release-iphoneos binaries carry no trace of it (ADR-005 §8.5).
    @State private var isStoreScoreboardPresented: Bool =
      CommandLine.arguments.contains("--ui-test")
      && CommandLine.arguments.contains("--ui-test-open-scoreboard")
  #endif
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
    // Universal Links (https://pastura.app/s/<id>) arrive as a browsing-web
    // user activity, NOT via onOpenURL (that fires only for the pastura://
    // custom scheme). Route the webpageURL through the same handleOpenURL
    // pipeline — DeepLinkURL.parse accepts both shapes and the gallery-index
    // trust boundary is unchanged (#1071).
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
      if let url = userActivity.webpageURL { handleOpenURL(url) }
    }
    // Drain triggers: fire whenever any signal that gates navigability
    // changes. `tryDrain` itself re-checks all preconditions, so spurious
    // triggers are cheap.
    .onChange(of: appStateKind) { _, _ in tryDrain() }
    .onChange(of: gate.sheetPresentationCount) { _, _ in tryDrain() }
    // D5.3: the drain must re-fire when ANY tab's path changes (a
    // simulation popped on a backgrounded tab unblocks the drain), so we
    // observe all four routers' paths, not just the selected tab's.
    .onChange(of: tabCoordinator.allRouters.map(\.path)) { _, _ in tryDrain() }
    .onChange(of: gate.pendingURL) { _, new in if new != nil { tryDrain() } }
    .onChange(of: scenePhase) { old, new in handleScenePhase(from: old, to: new) }
    // Reset source-attribution when the user pops all the way back. The
    // deep-linked gallery detail lands on the さがす (Search) tab (D5.2),
    // so the attribution clears when THAT tab's stack empties (D5.3) —
    // not when an unrelated tab happens to be at root.
    .onChange(of: tabCoordinator.searchRouter.path.isEmpty) { _, isEmpty in
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
    #if DEBUG
      // Screenshot-only scoreboard (see `isStoreScoreboardPresented`).
      // Deliberately NOT `.deepLinkGated()`: the store capture queues no deep
      // link, so this sheet stays invisible to `DeepLinkGate` (critic axis 7).
      .sheet(isPresented: $isStoreScoreboardPresented) {
        let sample = StoreScoreboardSample.current()
        ScoreboardSheet(scores: sample.scores, eliminated: sample.eliminated)
        .presentationDetents([.large])
      }
    #endif
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
        // Per-tab `AppRouter` is injected INSIDE each tab's NavigationStack
        // by RootTabView (D3) — deliberately not `.environment(router)`
        // here, which would collapse all tabs onto one stack.
        RootTabView(coordinator: tabCoordinator)
          // Phase B (ADR-017 #682): the "return to your running simulation"
          // pill, shown across tabs while a run is parked-away. Placed before
          // the `.environment` calls so it inherits `dependencies` +
          // `tabCoordinator`; it self-gates visibility via `shouldShowIndicator`
          // and carries the away-case memory-warning + scene-phase observers.
          .overlay { InFlightSimulationIndicator() }
          .environment(dependencies)
          .environment(gate)
          // `ModelManager` is exposed so Settings → Models can observe
          // state and drive switch / download / delete without threading
          // it through every intermediate view.
          .environment(modelManager)
          // The coordinator is exposed app-wide (in addition to driving
          // RootTabView) so a pushed `SimulationView` can publish its
          // leave-guard flag and resolve a deferred tab-switch for the
          // confirm-on-leave dialog (#673). Injected ABOVE the TabView is
          // safe — unlike the per-tab `AppRouter`, the coordinator is shared.
          .environment(tabCoordinator)
          .environment(\.lastDeepLinkedScenarioId, lastDeepLinkedScenarioId)
          // Suppress continuous animations under the XCUITest harness so the
          // app reaches "idle" between interactions (#728). Read once here;
          // leaf Views consume it via `@Environment(\.isUITestMode)`.
          .environment(\.isUITestMode, UITestMode.isActive)

      case .databaseRecovery(let message):
        // Reached only for a recoverable `DataError` (deterministic migration
        // failure). Splash z-orders above this (like `.error`); recovery shows
        // once the cold splash dismisses.
        VStack(spacing: 16) {
          Image(systemName: "externaldrive.badge.exclamationmark")
            .font(.largeTitle)
            .foregroundStyle(Color.danger)
          Text(String(localized: "Database Needs Recovery"))
            .font(.headline)
          Text(
            String(
              localized:
                "Pastura couldn't upgrade its database.\nYou can reset it to continue — your previous data is kept in a backup on this device."
            )
          )
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .multilineTextAlignment(.center)
          Text(message)
            // `inkSecondary`, not `muted`: design-system §8 makes `muted` a
            // deliberately sub-AA (≈3.3:1) quietude tier and says not to put
            // information that must be read there. This is the migration
            // failure text the user weighs before choosing a data-destroying
            // reset. `.caption` keeps it below the body copy in hierarchy.
            .foregroundStyle(Color.inkSecondary)
            .multilineTextAlignment(.center)
          Button(String(localized: "Reset Database"), role: .destructive) {
            Task { await recoverDatabase() }
          }
          // The ONE sanctioned `.borderedProminent`, and it is not the defect
          // the rule below catches. `role: .destructive` replaces the tint fill
          // with the system red, so this never resolves the moss tint that
          // measures white-on-fill at 3.03:1 light / 2.13:1 dark — system red
          // measures 3.55:1 / 3.41:1 and adapts on its own. Converting it to
          // `PasturaPrimaryButtonStyle` would fill it `mossDark` and make a
          // data-destroying action look like an ordinary primary CTA; the
          // style has no destructive variant, and adding one to carry a single
          // failure-screen button is not worth a new design-system branch.
          // §5.8's second objection to this style — that it opts into iOS 26's
          // Liquid Glass capsule — was considered and does not bite: the label
          // is text-only, so there is no glyph to be rendered into the fill
          // (the failure `HomePausedCard` records), and a system-red capsule on
          // a failure screen is the platform-conventional shape.
          // swiftlint:disable:next bordered_prominent_button_style
          .buttonStyle(.borderedProminent)
          // Retry is meaningful here even though only `.migrationFailed` reaches
          // this screen: a migration can fail transiently (disk full / lock at
          // migrate time), and a plain retry then succeeds without the
          // data-destroying reset. For a deterministic failure it re-routes back
          // here, and the user picks Reset.
          Button(String(localized: "Retry")) {
            appState = .initializing
          }
          .buttonStyle(.bordered)
          // Tertiary affordance: capture a bug report with the migration
          // error auto-attached, BEFORE the user resets and the failing DB
          // is moved aside (#580). Quieter than Reset/Retry so it doesn't
          // compete with recovery.
          Button(String(localized: "Report this problem")) {
            // Gate on splash dismissal: the recovery screen is occluded by
            // the splash overlay until `splashKind == nil` (see the
            // `deepLinkToast` render guard), so presenting the sheet mid
            // cold-splash-exit could race the transition. The button is
            // already unreachable under the opaque splash; this is the
            // belt-and-suspenders for the exit-animation frame.
            guard splashKind == nil else { return }
            isRecoveryReportSheetPresented = true
          }
          .font(.footnote)
          .padding(.top, 4)
          .accessibilityIdentifier("recovery.reportButton")
        }
        .padding()
        .reportSheet(
          isPresented: $isRecoveryReportSheetPresented,
          context: .migrationFailure(error: message))

      case .error(let message):
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(Color.danger)
          Text(String(localized: "Initialization Failed"))
            .font(.headline)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .multilineTextAlignment(.center)
          Button(String(localized: "Retry")) {
            appState = .initializing
          }
          .buttonStyle(PasturaPrimaryButtonStyle())
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
    case .databaseRecovery: return .databaseRecovery
    case .error: return .error
    }
  }

  private var deepLinkBlockReason: DeepLinkBlockReason? {
    switch appState {
    case .initializing: return .initializing
    case .needsModelSelection: return .modelSelection
    case .needsModelDownload: return .modelDownload
    case .databaseRecovery: return .databaseRecovery
    case .error: return .error
    case .ready:
      if gate.isSheetActive { return .sheetPresented }
      if isSimulationOnTop { return .simulationActive }
      return nil
    }
  }

  // D5.1 / D5.4: a `.simulation` on top of ANY tab's stack — not just the
  // selected tab's. Single source of truth read by all three consumers
  // (deep-link block reason, drain guard, warm-splash gate); the fold
  // lives on TabCoordinator. `// D5.4: any-tab — do not narrow`.
  private var isSimulationOnTop: Bool {
    tabCoordinator.isSimulationOnTop
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
      // D5.2 fixed-tab routing lives on the coordinator so the kernel is
      // unit-testable (`TabCoordinatorTests`); the rationale for selecting
      // さがす + plain-push is documented there.
      tabCoordinator.presentDeepLinkedGalleryScenario(scenario)
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
      // Capture-tooling / UI-test launch overrides. Extracted to a helper so
      // initialize() stays under SwiftLint's cyclomatic-complexity cap.
      if await handleDebugLaunchOverride() { return }
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
      } catch let dbError as DataError where dbError.isRecoverable {
        // Simulator: recovery rebuilds via OllamaService (no model path).
        pendingRecoveryModelPath = nil
        routeToRecovery(dbError)
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
      let llm = makeLlamaCppService(modelPath: modelPath, descriptor: descriptor)
      let deps = try AppDependencies.production(llmService: llm)
      // Register BG task handler early so iOS 26+ can launch us in background.
      deps.backgroundManager.register()
      PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)
      appState = .ready(deps)
    } catch let dbError as DataError where dbError.isRecoverable {
      // Device: capture the model path so recovery can rebuild the LLM
      // service from the (still-active) descriptor after the reset.
      pendingRecoveryModelPath = modelPath
      routeToRecovery(dbError)
    } catch {
      appState = .error(
        String(
          format: String(localized: "Database error: %@"), error.localizedDescription))
    }
  }

  /// Builds the on-device `LlamaCppService` from a model path + descriptor.
  /// Extracted so the migration-recovery path (#546) rebuilds it from the
  /// same five descriptor fields as `finalizeInit`, with no drift.
  private func makeLlamaCppService(
    modelPath: String, descriptor: ModelDescriptor
  ) -> LlamaCppService {
    LlamaCppService(
      modelPath: modelPath,
      stopSequence: descriptor.stopSequence,
      modelIdentifier: descriptor.displayName,
      systemPromptSuffix: descriptor.systemPromptSuffix,
      assistantPrefix: descriptor.assistantPrefix
    )
  }

  /// Logs and transitions to the consent-gated DB recovery screen (#546).
  private func routeToRecovery(_ dbError: DataError) {
    Self.logger.error(
      "DB init failed (recoverable); offering reset: \(dbError.localizedDescription, privacy: .public)"
    )
    appState = .databaseRecovery(dbError.localizedDescription)
  }

  /// Backs up the existing database, recreates a fresh one, and continues to
  /// `.ready`. Invoked from the recovery screen's "Reset Database" button
  /// after explicit user consent (#546).
  private func recoverDatabase() async {
    Self.logger.notice("DB recovery: user consented to reset")
    do {
      let deps = try makeRecoveredDependencies()
      deps.backgroundManager.register()
      PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)
      pendingRecoveryModelPath = nil
      appState = .ready(deps)
    } catch {
      appState = .error(
        String(
          format: String(localized: "Database recovery failed: %@"),
          error.localizedDescription))
    }
  }

  private func makeRecoveredDependencies() throws -> AppDependencies {
    if let modelPath = pendingRecoveryModelPath {
      // Device: rebuild the LLM service from the still-active descriptor.
      guard let descriptor = modelManager.activeDescriptor else {
        // App-layer invariant violation, not a real migration failure: the
        // active descriptor is guaranteed non-nil upstream (see finalizeInit).
        // `.migrationFailed` is reused only to satisfy the `throws` contract;
        // recoverDatabase() maps any throw here to `.error` with this message,
        // and never pattern-matches the case.
        throw DataError.migrationFailed(
          description: String(localized: "No active model descriptor resolvable from catalog"))
      }
      let llm = makeLlamaCppService(modelPath: modelPath, descriptor: descriptor)
      return try AppDependencies.recoverByBackingUpDatabase(llmService: llm)
    }
    #if DEBUG || targetEnvironment(simulator)
      // Simulator: OllamaService backend, no model path.
      return try AppDependencies.recoverByBackingUpDatabase()
    #else
      // Unreachable on production device — `finalizeInit` always sets
      // `pendingRecoveryModelPath` before routing to recovery. `.migrationFailed`
      // is a throws-contract filler (mapped to `.error` by recoverDatabase), not
      // a real migration signal.
      throw DataError.migrationFailed(
        description: String(localized: "Recovery requires an active model"))
    #endif
  }

  #if DEBUG
    /// UI-test-only bootstrap: constructs an in-memory `AppDependencies` with a
    /// deterministic `MockLLMService` and `StubGalleryService`, skips preset
    /// loading, and transitions directly to `.ready`. Avoids network, disk
    /// persistence, and the real LLM — all of which introduce non-determinism
    /// that would make navigation regressions hard to catch reliably.
    private func setupUITestState() async {
      do {
        // `--ui-test-slow-llm`: hold the run in-flight for the whole UI test so a
        // started simulation never completes (the simulator can't run real
        // inference). Lets the Phase B park-and-return flow be exercised
        // end-to-end (the run blocks in the first `generate`, so `registry.isActive`
        // stays true throughout — `InFlightIndicatorReconnectUITests`).
        //
        // `blockGenerateUntilSignal()` blocks INSIDE `generate` on an explicit
        // signal — wall-clock-INDEPENDENT, so a slow CI runner can never expire
        // the hold mid-test (#719; the old `generateDelay` wall-clock sleep was
        // calibrated to a 120s constant against 109–286s CI timing variance).
        // The test never unblocks; tearDown's `terminate()` ends the run.
        //
        // NOT `suspendOnControllerAttach()`: that *parks* the run pre-generate via
        // the controller, which the test's `.viewHide` resume gate
        // (`requestResume(.viewHide)`) would clear — letting the generate run on,
        // exhaust the empty `responses: []`, and error-terminate the run. The two
        // mechanisms are deliberately distinct (blocked-in-generate vs parked).
        let llm = MockLLMService(responses: [])
        if CommandLine.arguments.contains("--ui-test-slow-llm") {
          llm.blockGenerateUntilSignal()
        }
        // Normalize keep-running-on-leave every --ui-test launch (a real Bool
        // write; a `-key YES` launch arg lands as a String that `FeatureFlags`'
        // `object(forKey:) as? Bool` reads as nil → default false). Setting it
        // explicitly both ways prevents the persisted flag leaking into later
        // UI-test runs on the same simulator.
        FeatureFlags.setKeepRunningOnLeave(
          CommandLine.arguments.contains("--ui-test-keep-running"))
        let gallery = Self.uiTestGalleryService()
        let editorSeedYAML =
          CommandLine.arguments.contains("--ui-test-editor-seed-yaml")
          ? StubScenarioSeeder.editorSeedYAML : nil
        let deps = try AppDependencies.inMemory(
          llmService: llm,
          galleryService: gallery,
          uiTestEditorSeedYAML: editorSeedYAML
        )
        // Default-on base seed (1 Home row). --ui-test-seed-empty-inventory
        // skips it so the Home/Past-Results empty states render for the
        // screenshot tour (#811). The inversion is load-bearing: plain
        // --ui-test (no arg) still seeds, so BackGestureTests / EditorReloadTests
        // keep their deterministic "before" row.
        if !CommandLine.arguments.contains("--ui-test-seed-empty-inventory") {
          try await StubScenarioSeeder.seed(into: deps.scenarioRepository)
        }
        // Rich Home fixture (presets + a gallery-sourced "shared" row) is
        // opt-in for the ui-tour Home captures. Also implied by
        // --ui-test-seed-paused, since the resume card reads its metadata from
        // the rich seed's scenario (StubPausedRunSeeder dependency).
        let wantsRichHome =
          CommandLine.arguments.contains("--ui-test-seed-home-rich")
          || CommandLine.arguments.contains("--ui-test-seed-paused")
        if wantsRichHome {
          try await StubScenarioSeeder.seedRichHome(into: deps.scenarioRepository)
        }
        // Paused-run fixture surfaces the Home resume card (d3-with). Opt-in so
        // plain --ui-test keeps the card hidden (d3-without).
        if CommandLine.arguments.contains("--ui-test-seed-paused") {
          try await StubPausedRunSeeder.seed(
            simulationRepository: deps.simulationRepository)
        }
        // Past Results fixtures are opt-in so plain --ui-test runs keep
        // exercising the empty state (ScreenshotTourTests opts in). Exactly one
        // fixture is seeded per launch (see `resultSeedFixture`) — the two
        // marketing transcripts drive the Zenn-article inference screenshots.
        if let fixture = Self.resultSeedFixture() {
          try await StubResultSeeder.seed(
            simulationRepository: deps.simulationRepository,
            turnRepository: deps.turnRepository,
            codePhaseEventRepository: deps.codePhaseEventRepository,
            fixture: fixture)
        }
        // Deep-link injection for UI tests: queue a `pastura://` URL before
        // `.ready` so the existing gate drains it via the `appStateKind`
        // onChange once deps are up — the same queue-then-drain path a real
        // pre-`.ready` `onOpenURL` would take. Exercises D5 deep-link →
        // Search-tab routing end-to-end (DeepLinkTabRoutingUITests).
        if let idx = CommandLine.arguments.firstIndex(of: "--ui-test-open-deeplink"),
          idx + 1 < CommandLine.arguments.count,
          let url = URL(string: CommandLine.arguments[idx + 1]) {
          gate.pendingURL = url
        }
        appState = .ready(deps)
      } catch {
        appState = .error("UI test setup failed: \(error.localizedDescription)")
      }
    }

    /// Selects the UI-test gallery service from launch args. Gallery sad-path
    /// captures for the ui-refine L5/L6 lenses (#811):
    /// `--ui-test-seed-gallery-offline` → `.empty` ("Gallery Unavailable");
    /// `--ui-test-seed-empty-gallery` → `.loaded` with a galleryEmpty card
    /// ("No scenarios available yet"). Plain `--ui-test` keeps the canary.
    private static func uiTestGalleryService() -> StubGalleryService {
      let args = CommandLine.arguments
      if args.contains("--ui-test-seed-gallery-offline") {
        return StubGalleryService.uiTestOfflineGallery()
      }
      if args.contains("--ui-test-seed-empty-gallery") {
        return StubGalleryService.uiTestEmptyGallery()
      }
      return StubGalleryService.uiTestPreset()
    }

    /// Selects the Past-Results seed fixture from launch args, or `nil` when
    /// none is requested. Exactly one fixture is seeded per launch; the two
    /// marketing transcripts (wordwolf / prisoners) drive the Zenn-article
    /// inference screenshots.
    private static func resultSeedFixture() -> StubResultSeeder.MarketingFixture? {
      let args = CommandLine.arguments
      if args.contains("--ui-test-seed-results-wordwolf") { return .wordWolf }
      if args.contains("--ui-test-seed-results-prisoners") { return .prisoners }
      if args.contains("--ui-test-seed-results") { return .defaultAliceBob }
      return nil
    }

    /// Dispatches DEBUG-only launch overrides. Returns `true` when an override
    /// fired (caller returns early), `false` to fall through to normal init.
    /// `--capture-demo` must be handled before `initialize()`'s `#if
    /// targetEnvironment(simulator)` branch, which otherwise goes straight to
    /// `.ready` on the simulator and never reaches `.needsModelDownload`.
    private func handleDebugLaunchOverride() async -> Bool {
      if CommandLine.arguments.contains("--capture-demo") {
        setupCaptureDemoState()
        return true
      }
      if CommandLine.arguments.contains("--ui-test") {
        await setupUITestState()
        return true
      }
      return false
    }

    /// Capture-tooling-only bootstrap (`scripts/motion-capture.sh demo`): seed
    /// the active descriptor into `.downloading` and route to
    /// `.needsModelDownload` so `ModelDownloadHostView` renders the demo replay
    /// screen for recording. Starts NO real download (no `startDownload`) — the
    /// demo replay plays independently of download progress (ADR-007 §4.2).
    private func setupCaptureDemoState() {
      // `activeDescriptor` is nil only with an empty catalog (never in
      // production). Guard loudly: without it the seed can't fire, the host
      // routes to `.plainProgress`, and the capture silently records a
      // no-typing screen that the script's size check can't flag.
      guard let descriptor = modelManager.activeDescriptor else {
        Self.logger.error(
          "--capture-demo: no active descriptor; demo replay will not render")
        appState = .needsModelDownload
        return
      }
      modelManager.captureSeedDownloadingState(for: descriptor)
      appState = .needsModelDownload
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
            format: String(
              localized:
                "Downloading %@ on cellular may use significant data. Wi-Fi is recommended."
            ), ModelSettingsRow.formattedFileSize(descriptor.fileSize)))
      }
  }
}
