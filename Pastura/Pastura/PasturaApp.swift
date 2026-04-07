import SwiftUI

@main
struct PasturaApp: App {
  @State private var dependencies: AppDependencies?

  var body: some Scene {
    WindowGroup {
      Group {
        if let dependencies {
          HomeView()
            .environment(dependencies)
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
      // Fatal: cannot proceed without database
      fatalError("Failed to initialize database: \(error)")
    }
  }
}
