import Foundation

/// ViewModel for the home screen scenario list.
///
/// Fetches scenarios from the repository and splits them into presets
/// and user-created groups. Supports pull-to-refresh and deletion.
@Observable
final class HomeViewModel {
  private(set) var presets: [ScenarioRecord] = []
  private(set) var userScenarios: [ScenarioRecord] = []
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  private let repository: any ScenarioRepository

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  func loadScenarios() async {
    isLoading = true
    errorMessage = nil

    do {
      let all = try await offMain { [repository] in
        try repository.fetchAll()
      }
      presets = all.filter(\.isPreset)
      userScenarios = all.filter { !$0.isPreset }
    } catch {
      errorMessage = "Failed to load scenarios: \(error.localizedDescription)"
    }

    isLoading = false
  }

  func deleteScenario(_ id: String) async {
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      userScenarios.removeAll { $0.id == id }
    } catch {
      errorMessage = "Failed to delete scenario: \(error.localizedDescription)"
    }
  }
}
