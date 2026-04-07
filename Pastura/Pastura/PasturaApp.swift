import SwiftUI

@main
struct PasturaApp: App {
  @State private var dependencies: AppDependencies?
  @State private var initError: String?

  var body: some Scene {
    WindowGroup {
      Group {
        if let dependencies {
          HomeView()
            .environment(dependencies)
        } else if let initError {
          VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
              .font(.largeTitle)
              .foregroundStyle(.red)
            Text("Initialization Failed")
              .font(.headline)
            Text(initError)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button("Retry") {
              self.initError = nil
              Task { await initialize() }
            }
            .buttonStyle(.borderedProminent)
          }
          .padding()
        } else {
          ProgressView("Initializing...")
            .task {
              await initialize()
            }
        }
      }
    }
  }

  private func initialize() async {
    do {
      let deps = try AppDependencies.production()

      // Load presets on first launch
      PresetLoader.loadPresetsIfNeeded(repository: deps.scenarioRepository)

      dependencies = deps
    } catch {
      initError = "Database error: \(error.localizedDescription)"
    }
  }
}
