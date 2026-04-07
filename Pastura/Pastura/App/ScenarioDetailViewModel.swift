import Foundation

// @MainActor is explicit for Xcode 16.x CI compatibility. See #37.

/// ViewModel for the scenario detail screen.
///
/// Parses the YAML definition into a `Scenario` for rich display,
/// validates before launch, and estimates inference count.
@MainActor @Observable
final class ScenarioDetailViewModel {
  private(set) var record: ScenarioRecord?
  private(set) var scenario: Scenario?
  private(set) var estimatedInferences: Int = 0
  private(set) var validationError: String?
  private(set) var isLoading = false
  private(set) var errorMessage: String?

  /// Whether the scenario can be launched (valid + within limits).
  var canRun: Bool { scenario != nil && validationError == nil }

  private let repository: any ScenarioRepository
  private let loader = ScenarioLoader()
  private let validator = ScenarioValidator()

  init(repository: any ScenarioRepository) {
    self.repository = repository
  }

  func load(scenarioId: String) async {
    isLoading = true
    errorMessage = nil
    validationError = nil

    do {
      guard
        let fetched = try await offMain({ [repository] in
          try repository.fetchById(scenarioId)
        })
      else {
        errorMessage = "Scenario not found"
        isLoading = false
        return
      }

      record = fetched
      let parsed = try loader.load(yaml: fetched.yamlDefinition)
      scenario = parsed
      estimatedInferences = ScenarioLoader.estimateInferenceCount(parsed)

      // Validate
      do {
        _ = try validator.validate(parsed)
      } catch {
        validationError = error.localizedDescription
      }
    } catch {
      errorMessage = "Failed to load scenario: \(error.localizedDescription)"
    }

    isLoading = false
  }

  func deleteScenario() async -> Bool {
    guard let id = record?.id else { return false }
    do {
      try await offMain { [repository] in
        try repository.delete(id)
      }
      return true
    } catch {
      errorMessage = "Failed to delete: \(error.localizedDescription)"
      return false
    }
  }
}
