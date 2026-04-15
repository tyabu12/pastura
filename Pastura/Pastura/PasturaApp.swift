import SwiftUI

@main
struct PasturaApp: App {
  var body: some Scene {
    // RootView lives inside WindowGroup so each scene (iPad multi-window,
    // iPhone single window) gets its own @State — including its own
    // AppRouter / NavigationStack path. App-struct-level @State would be
    // shared across all scenes.
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
  /// Model needs to be downloaded before the app can run.
  case needsModelDownload
  /// App is ready — dependencies are initialized.
  case ready(AppDependencies)
  /// A fatal initialization error occurred.
  case error(String)
}

/// Per-scene root view. Owns the model-download state machine, the
/// dependency container, and the `AppRouter` that drives the root
/// `NavigationStack`'s path.
private struct RootView: View {
  @State private var appState: AppState = .initializing
  @State private var modelManager = ModelManager()
  @State private var router = AppRouter()

  var body: some View {
    Group {
      switch appState {
      case .initializing:
        ProgressView("Initializing...")
          .task {
            await initialize()
          }

      case .needsModelDownload:
        ModelDownloadView(modelManager: modelManager)
          .onChange(of: modelManager.state) { _, newState in
            if case .ready(let modelPath) = newState {
              Task { await finalizeInit(modelPath: modelPath) }
            }
          }

      case .ready(let dependencies):
        HomeView()
          .environment(dependencies)
          .environment(router)

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

  private func initialize() async {
    #if DEBUG
      if CommandLine.arguments.contains("--ui-test") {
        await setupUITestState()
        return
      }
    #endif
    #if targetEnvironment(simulator)
      // On simulator, use OllamaService directly — no model download needed.
      do {
        let deps = try AppDependencies.production()
        PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)
        appState = .ready(deps)
      } catch {
        appState = .error("Database error: \(error.localizedDescription)")
      }
    #else
      modelManager.checkModelStatus()
      switch modelManager.state {
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
    do {
      let llm = LlamaCppService(modelPath: modelPath)
      let deps = try AppDependencies.production(llmService: llm)
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
        let gallery = StubGalleryService(
          index: GalleryIndex(version: 1, updatedAt: "2026-04-15", scenarios: [])
        )
        let deps = try AppDependencies.inMemory(llmService: llm, galleryService: gallery)
        appState = .ready(deps)
      } catch {
        appState = .error("UI test setup failed: \(error.localizedDescription)")
      }
    }
  #endif
}
