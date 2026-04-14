import Foundation

/// Central dependency container for the application.
///
/// Initializes `DatabaseManager`, all repositories, and provides an LLM service
/// factory. Injected into the SwiftUI environment at the app root. Views and
/// ViewModels access repositories and services through this container.
@Observable
final class AppDependencies: @unchecked Sendable {
  // @unchecked Sendable: all user-defined stored properties are `let` with Sendable types.
  // The @Observable macro adds an ObservationRegistrar which is itself Sendable (thread-safe).
  let scenarioRepository: any ScenarioRepository
  let simulationRepository: any SimulationRepository
  let turnRepository: any TurnRepository

  /// The LLM service used for simulation execution.
  /// Defaults to `OllamaService` for development.
  let llmService: any LLMService

  /// Manager for iOS 26+ background simulation continuation.
  /// Registered at app launch; used by `SimulationViewModel` when the user
  /// opts into background continuation via the toggle in `SimulationView`.
  let backgroundManager: BackgroundSimulationManager

  private let databaseManager: DatabaseManager

  init(
    databaseManager: DatabaseManager,
    llmService: (any LLMService)? = nil,
    backgroundManager: BackgroundSimulationManager = BackgroundSimulationManager()
  ) {
    self.databaseManager = databaseManager
    let writer = databaseManager.dbWriter
    self.scenarioRepository = GRDBScenarioRepository(dbWriter: writer)
    self.simulationRepository = GRDBSimulationRepository(dbWriter: writer)
    self.turnRepository = GRDBTurnRepository(dbWriter: writer)
    self.llmService = llmService ?? OllamaService()
    self.backgroundManager = backgroundManager
  }

  /// Creates a production instance with persistent SQLite storage.
  static func production() throws -> AppDependencies {
    let dbPath = Self.databasePath()
    let manager = try DatabaseManager.persistent(at: dbPath)
    return AppDependencies(databaseManager: manager)
  }

  /// Creates a production instance with a specific LLM service.
  ///
  /// Used for on-device LlamaCppService where the model path is known only
  /// after download completes. The LLM service is immutable once set.
  static func production(llmService: any LLMService) throws -> AppDependencies {
    let dbPath = Self.databasePath()
    let manager = try DatabaseManager.persistent(at: dbPath)
    return AppDependencies(databaseManager: manager, llmService: llmService)
  }

  /// Creates a test/preview instance with in-memory storage.
  static func inMemory(llmService: (any LLMService)? = nil) throws -> AppDependencies {
    let manager = try DatabaseManager.inMemory()
    return AppDependencies(databaseManager: manager, llmService: llmService)
  }

  // MARK: - Private

  private static func databasePath() -> String {
    let appSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory

    let appDir = appSupport.appendingPathComponent("Pastura", isDirectory: true)
    try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

    return appDir.appendingPathComponent("pastura.sqlite").path
  }
}

// MARK: - Off-MainActor Helper

/// Runs a synchronous throwing closure off the MainActor.
///
/// Repository methods are synchronous `throws` (GRDB convention), but ViewModels
/// run on MainActor. This helper dispatches DB work to avoid blocking the main thread.
func offMain<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
  try await Task.detached(operation: work).value
}
