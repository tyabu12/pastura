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

  var body: some View {
    ZStack {
      mainContent
      deepLinkToast
    }
    .onOpenURL { handleOpenURL($0) }
    // Drain triggers: fire whenever any signal that gates navigability
    // changes. `tryDrain` itself re-checks all preconditions, so spurious
    // triggers are cheap.
    .onChange(of: appStateKind) { _, _ in tryDrain() }
    .onChange(of: gate.sheetPresentationCount) { _, _ in tryDrain() }
    .onChange(of: router.path) { _, _ in tryDrain() }
    .onChange(of: gate.pendingURL) { _, new in
      if new != nil { tryDrain() }
    }
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
  }

  // MARK: - Content

  @ViewBuilder
  private var mainContent: some View {
    Group {
      switch appState {
      case .initializing:
        ProgressView("Initializing...")
          .task {
            await initialize()
          }

      case .needsModelSelection:
        ModelPickerView(modelManager: modelManager) { pickedID in
          modelManager.setActiveModel(pickedID)
          // Transition to the existing download flow — `checkModelStatus()`
          // already ran during `initialize()`, so `activeState` is
          // `.notDownloaded` and `DemoReplayHostView` will prompt the user
          // to start the download for the newly-active descriptor.
          appState = .needsModelDownload
        }

      case .needsModelDownload:
        DemoReplayHostView(modelManager: modelManager)
          .onChange(of: modelManager.activeState) { _, newState in
            if case .ready(let modelPath) = newState {
              Task { await finalizeInit(modelPath: modelPath) }
            }
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
            .foregroundStyle(.red)
          Text("Initialization Failed")
            .font(.headline)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button("Retry") {
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
    if gate.pendingURL != nil, let reason = deepLinkBlockReason {
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
          localized: "Open Share Board to refresh, then try the link again.")
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
        appState = .error("Database error: \(error.localizedDescription)")
      }
    #else
      modelManager.checkModelStatus()
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
      case .unsupportedDevice, .notDownloaded, .error:
        appState = .needsModelDownload
      case .checking, .downloading:
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
      appState = .error("No active model descriptor resolvable from catalog")
      return
    }
    do {
      let llm = LlamaCppService(
        modelPath: modelPath,
        stopSequence: descriptor.stopSequence,
        modelIdentifier: descriptor.displayName,
        systemPromptSuffix: descriptor.systemPromptSuffix
      )
      let deps = try AppDependencies.production(llmService: llm)
      // Register BG task handler early so iOS 26+ can launch us in background.
      deps.backgroundManager.register()
      PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)
      appState = .ready(deps)
    } catch {
      appState = .error("Database error: \(error.localizedDescription)")
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
        appState = .ready(deps)
      } catch {
        appState = .error("UI test setup failed: \(error.localizedDescription)")
      }
    }
  #endif
}
