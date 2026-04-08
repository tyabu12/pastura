import SwiftUI

@main
struct PasturaApp: App {
  @State private var appState: AppState = .initializing
  @State private var modelManager = ModelManager()

  var body: some Scene {
    WindowGroup {
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
  }

  private func initialize() async {
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
}

// MARK: - App State

extension PasturaApp {
  /// Top-level app navigation state.
  enum AppState {
    /// App is initializing (checking model, setting up database).
    case initializing
    /// Model needs to be downloaded before the app can run.
    case needsModelDownload
    /// App is ready — dependencies are initialized.
    case ready(AppDependencies)
    /// A fatal initialization error occurred.
    case error(String)
  }
}
