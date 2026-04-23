import Foundation

/// Central dependency container for the application.
///
/// Initializes `DatabaseManager`, all repositories, and provides an LLM service
/// factory. Injected into the SwiftUI environment at the app root. Views and
/// ViewModels access repositories and services through this container.
@Observable
final class AppDependencies: @unchecked Sendable {
  // @unchecked Sendable rationale: every stored property is either
  //   - a `let` with a Sendable type, or
  //   - a `var` (`llmService`) mutated exclusively on MainActor — the
  //     class is MainActor-isolated by project default, and the only
  //     mutator (`regenerateLLMService(_:)`) is annotated explicitly.
  // The @Observable macro adds an ObservationRegistrar which is itself
  // Sendable (thread-safe).
  let scenarioRepository: any ScenarioRepository
  let simulationRepository: any SimulationRepository
  let turnRepository: any TurnRepository
  let codePhaseEventRepository: any CodePhaseEventRepository

  /// The LLM service used for simulation execution.
  ///
  /// Callers must pass an explicit `llmService` in Release-iphoneos builds
  /// (see ADR-005 §8 — dev-only backends like `OllamaService` are excluded
  /// from App-Store-review-bound binaries). The `nil`-fallback construction
  /// is only available in Debug or Simulator builds.
  ///
  /// Mutable to support active-model switching from Settings. Only
  /// `regenerateLLMService(_:)` mutates this — see that method for the
  /// surrounding "no-simulation-in-flight" invariant.
  private(set) var llmService: any LLMService

  /// Manager for iOS 26+ background simulation continuation.
  /// Registered at app launch; used by `SimulationViewModel` when the user
  /// opts into background continuation via the toggle in `SimulationView`.
  let backgroundManager: BackgroundSimulationManager

  /// Service that fetches the remote Share Board (gallery) index and YAMLs.
  let galleryService: any GalleryService

  /// Process-wide counter tracking whether a simulation is in flight.
  /// Observed by the Settings Models section to disable model switching
  /// while inference is running. Entered / left exclusively from
  /// `SimulationViewModel.run()`.
  let simulationActivityRegistry: SimulationActivityRegistry

  #if DEBUG
    /// YAML pre-filled into the scenario editor when the Home screen's
    /// "New Scenario" menu is tapped under `--ui-test`. `nil` in all other
    /// builds and flows. Populated by `setupUITestState()` from the
    /// `--ui-test-editor-seed-yaml` launch argument; consumed by `HomeView`
    /// so test code does not read `CommandLine.arguments` from a view.
    ///
    /// DEBUG-gated to match the existing UITestSupport surface
    /// (`StubGalleryService`, `StubScenarioSeeder`) and to keep
    /// Release-iphoneos binaries free of UI-test plumbing per ADR-005 §8.
    let uiTestEditorSeedYAML: String?
  #endif

  private let databaseManager: DatabaseManager

  init(
    databaseManager: DatabaseManager,
    llmService: (any LLMService)? = nil,
    backgroundManager: BackgroundSimulationManager = BackgroundSimulationManager(),
    galleryService: (any GalleryService)? = nil,
    simulationActivityRegistry: SimulationActivityRegistry = SimulationActivityRegistry(),
    uiTestEditorSeedYAML: String? = nil
  ) {
    self.simulationActivityRegistry = simulationActivityRegistry
    self.databaseManager = databaseManager
    let writer = databaseManager.dbWriter
    self.scenarioRepository = GRDBScenarioRepository(dbWriter: writer)
    self.simulationRepository = GRDBSimulationRepository(dbWriter: writer)
    self.turnRepository = GRDBTurnRepository(dbWriter: writer)
    self.codePhaseEventRepository = GRDBCodePhaseEventRepository(dbWriter: writer)
    if let llmService {
      self.llmService = llmService
    } else {
      // ADR-005 §8: `OllamaService` ships only in Debug / Simulator builds.
      // In Release-iphoneos the fallback is unreachable by construction —
      // `production(llmService:)` is the only caller and requires the arg.
      #if DEBUG || targetEnvironment(simulator)
        self.llmService = OllamaService()
      #else
        preconditionFailure("AppDependencies requires an explicit llmService in Release builds")
      #endif
    }
    self.backgroundManager = backgroundManager
    self.galleryService = galleryService ?? URLSessionGalleryService()
    #if DEBUG
      self.uiTestEditorSeedYAML = uiTestEditorSeedYAML
    #endif
  }

  #if DEBUG || targetEnvironment(simulator)
    /// Creates a production instance with persistent SQLite storage and the
    /// default `OllamaService` LLM backend.
    ///
    /// Gated to Debug / Simulator per ADR-005 §8 — Release-iphoneos callers
    /// must use `production(llmService:)` with a shipping backend (e.g.
    /// `LlamaCppService`).
    static func production() throws -> AppDependencies {
      let dbPath = Self.databasePath()
      let manager = try DatabaseManager.persistent(at: dbPath)
      return AppDependencies(databaseManager: manager)
    }
  #endif

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
  static func inMemory(
    llmService: (any LLMService)? = nil,
    galleryService: (any GalleryService)? = nil,
    uiTestEditorSeedYAML: String? = nil
  ) throws -> AppDependencies {
    let manager = try DatabaseManager.inMemory()
    return AppDependencies(
      databaseManager: manager,
      llmService: llmService,
      galleryService: galleryService,
      uiTestEditorSeedYAML: uiTestEditorSeedYAML
    )
  }

  // MARK: - Active-model switching

  /// Replaces the active LLM service after the user switches the active
  /// model from Settings. The previous service is released; if its backend
  /// allocates native resources (e.g. a llama.cpp context), those are
  /// freed as the reference count drops.
  ///
  /// - Important: Callers MUST ensure no simulation is currently in
  ///   flight — the UI gates the Settings switch affordance on
  ///   `simulationActivityRegistry.isActive == false`, and this method
  ///   does NOT re-check. Swapping mid-run would leave
  ///   `SimulationViewModel.currentLLM` pointing at the old instance
  ///   while `deps.llmService` points at the new one; the next
  ///   `loadModel()` on the stale reference could race the new
  ///   instance's init sequence.
  ///
  /// - Parameter newService: The newly-constructed service (typically
  ///   `LlamaCppService` wired to the newly-active descriptor's
  ///   stopSequence / systemPromptSuffix / model path).
  @MainActor
  func regenerateLLMService(_ newService: any LLMService) {
    self.llmService = newService
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
