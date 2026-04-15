import Foundation

/// A single displayable entry in the simulation log.
struct LogEntry: Identifiable {
  let id = UUID()
  let timestamp = Date()
  let kind: Kind

  enum Kind {
    case agentOutput(agent: String, output: TurnOutput, phaseType: PhaseType)
    case phaseStarted(phaseType: PhaseType)
    case roundStarted(round: Int, totalRounds: Int)
    case roundCompleted(round: Int, scores: [String: Int])
    case scoreUpdate(scores: [String: Int])
    case elimination(agent: String, voteCount: Int)
    case assignment(agent: String, value: String)
    case summary(text: String)
    case voteResults(votes: [String: String], tallies: [String: Int])
    case pairingResult(agent1: String, action1: String, agent2: String, action2: String)
    case error(String)
  }
}

/// Speed multiplier options for simulation playback.
enum PlaybackSpeed: Double, CaseIterable, Identifiable {
  case normal = 1.0
  case fast = 0.5
  case fastest = 0.0

  var id: Double { rawValue }

  var label: String {
    switch self {
    case .normal: "1x"
    case .fast: "1.5x"
    case .fastest: "Max"
    }
  }
}

/// ViewModel for the live simulation execution screen.
///
/// Consumes `AsyncStream<SimulationEvent>` from `SimulationRunner`, applies
/// `ContentFilter`, persists turn records, and manages pause/resume + LLM lifecycle.
@Observable
final class SimulationViewModel {
  // MARK: - Published State

  private(set) var logEntries: [LogEntry] = []
  private(set) var scores: [String: Int] = [:]
  private(set) var eliminated: [String: Bool] = [:]
  private(set) var currentRound = 0
  private(set) var totalRounds = 0
  private(set) var thinkingAgents: Set<String> = []
  private(set) var isRunning = false
  private(set) var isCompleted = false
  private(set) var isCancelled = false
  // Set by the main run() loop and by the BG continuation extension (in a separate file);
  // dropping private(set) allows cross-file extension access without a helper method.
  var errorMessage: String?
  var showAllThoughts = false
  var showDebugOutput = false
  var speed: PlaybackSpeed = .normal

  var isPaused: Bool {
    get { runner.isPaused }
    set { runner.isPaused = newValue }
  }

  // MARK: - Background continuation state

  /// Whether the user has enabled background simulation continuation.
  /// The toggle only takes effect if `canEnableBackgroundContinuation` is true.
  /// Set by the BG continuation extension (in a separate file).
  var isBackgroundContinuationEnabled = false

  /// Whether background continuation is available on this device/OS.
  /// Requires iOS 26+ and `LlamaCppService` (for GPU↔CPU switching).
  var canEnableBackgroundContinuation: Bool {
    guard #available(iOS 26, *) else { return false }
    guard backgroundManager?.isSupported == true else { return false }
    // Only LlamaCppService supports reloadModel; other backends can't switch modes.
    return currentLLM is LlamaCppService
  }

  // MARK: - Dependencies

  private let runner: SimulationRunner
  private let contentFilter: ContentFilter
  private let simulationRepository: any SimulationRepository
  private let turnRepository: any TurnRepository
  // Accessed from the BG continuation extension in SimulationViewModel+Background.swift
  let backgroundManager: BackgroundSimulationManager?
  private var simulationId: String?

  /// The LLM service currently driving the simulation — captured from `run(scenario:llm:)`
  /// so background transition handlers can reload the model without a new parameter.
  /// Accessed from the BG continuation extension.
  var currentLLM: (any LLMService)?

  /// True if the LLM is currently loaded in CPU-only mode (for background inference).
  /// Toggled by `switchToCPUInference` / `switchToGPUInference` in the BG extension.
  var isOnCPU = false

  /// True while the LLM model is being reloaded (GPU↔CPU switch).
  /// Surfaced to the UI so it can show a "Reloading model..." overlay —
  /// reload takes 3-8 seconds (model re-read from disk), most noticeable
  /// on foreground return from a background simulation.
  var isReloadingModel = false

  /// Holds the currently running simulation task for cancellation support.
  /// Set by the caller (SimulationView) after launching `run()` in a Task.
  /// Memory warning or explicit user action can cancel via `cancelSimulation()`.
  var runTask: Task<Void, Never>?

  /// Cooperative suspend/resume channel for the active inference. Created per
  /// `run()` call and attached to the LLM so scene-phase / BG-task handlers
  /// (in the +Background extension) can interrupt an in-flight `generate`.
  /// Cleared on `run()` exit.
  var suspendController: SuspendController?

  // Serial persistence queue — guarantees TurnRecords are written to the DB in
  // the same order events arrive. Without this, independent Task.detached calls
  // race and createdAt-based ordering in fetchBySimulationId becomes unreliable.
  private var persistenceContinuation: AsyncStream<TurnRecord>.Continuation?
  private var persistenceTask: Task<Void, Never>?

  /// Per-simulation sequence counter for deterministic TurnRecord ordering.
  /// Incremented synchronously on MainActor — no lock needed.
  private var turnSequence = 0

  init(
    runner: SimulationRunner = SimulationRunner(),
    contentFilter: ContentFilter = ContentFilter(),
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository,
    backgroundManager: BackgroundSimulationManager? = nil
  ) {
    self.runner = runner
    self.contentFilter = contentFilter
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
    self.backgroundManager = backgroundManager
  }

  // MARK: - Simulation Lifecycle

  /// Cancels a running simulation.
  /// Task cancellation terminates the runner's AsyncStream; the `for await`
  /// loop exits and post-loop cleanup runs.
  func cancelSimulation() {
    runTask?.cancel()
    isCancelled = true
    // Release a generate currently parked in `awaitResume()` so cancellation
    // propagates promptly from a suspended state. Idempotent per contract.
    suspendController?.resume()
    // Events emitted after cancellation are dropped by the terminated AsyncStream,
    // so clear UI "in-progress" state here to avoid stuck "thinking..." indicators.
    thinkingAgents.removeAll()
  }

  /// Starts the simulation, consuming events and persisting results.
  func run(scenario: Scenario, llm: any LLMService) async {
    currentLLM = llm
    isRunning = true
    isCompleted = false
    isCancelled = false
    errorMessage = nil
    logEntries = []
    scores = Dictionary(uniqueKeysWithValues: scenario.personas.map { ($0.name, 0) })
    eliminated = Dictionary(uniqueKeysWithValues: scenario.personas.map { ($0.name, false) })
    totalRounds = scenario.rounds

    // Create simulation record
    let simId = UUID().uuidString
    simulationId = simId
    let initialState = SimulationState.initial(for: scenario)
    await createSimulationRecord(simId: simId, scenario: scenario, state: initialState)

    turnSequence = 0

    // Attach BEFORE loadModel so scene-phase handlers can signal suspend as
    // soon as run() is in flight.
    let controller = SuspendController()
    suspendController = controller
    await llm.attachSuspendController(controller)

    // Start serial persistence consumer before any events can arrive.
    startPersistenceConsumer()
    // Guarantee cleanup in ALL exit paths (LLM load failure, cancellation, etc.)
    defer {
      // Release any parked generate before tearing down state. Idempotent.
      controller.resume()
      persistenceContinuation?.finish()
      backgroundManager?.completeTask(success: isCompleted)
      isRunning = false
      currentLLM = nil
      suspendController = nil
    }

    // Load LLM model
    do {
      try await llm.loadModel()
    } catch {
      errorMessage = "Failed to load LLM: \(error.localizedDescription)"
      await finalizeSimulationStatus()
      return
    }

    for await event in runner.run(
      scenario: scenario, llm: llm, suspendController: controller
    ) {
      // Apply speed delay (for non-instant playback)
      if speed != .fastest {
        try? await Task.sleep(for: .milliseconds(Int(200 * speed.rawValue)))
      }

      handleEvent(event, scenario: scenario)
    }

    // Drain persistence queue before marking simulation as completed.
    // finish() is idempotent; defer also calls it for early-return paths.
    persistenceContinuation?.finish()
    await persistenceTask?.value

    // Cleanup
    try? await llm.unloadModel()
    await finalizeSimulationStatus()
  }

  // MARK: - Event Handling

  // internal (not private) to allow direct unit testing via @testable import
  func handleEvent(_ event: SimulationEvent, scenario: Scenario) {
    switch event {
    case .roundStarted(let round, let total):
      handleRoundStarted(round: round, total: total)
    case .roundCompleted(let round, let newScores):
      handleRoundCompleted(round: round, scores: newScores)
    case .phaseStarted(let phaseType, _):
      logEntries.append(LogEntry(kind: .phaseStarted(phaseType: phaseType)))
    case .phaseCompleted, .simulationPaused:
      // No-op — `.simulationPaused` is a runner-side acknowledgement of the
      // user-initiated pause flow; the UI already reflects `isPaused` set
      // synchronously by the pause button. Background-driven suspend uses
      // the SuspendController path instead.
      break
    case .agentOutput(let agent, let output, let phaseType):
      handleAgentOutput(agent: agent, output: output, phaseType: phaseType)
    case .simulationCompleted:
      isCompleted = true
    case .error(let simError):
      errorMessage = "\(simError)"
      logEntries.append(LogEntry(kind: .error("\(simError)")))
    case .inferenceStarted(let agent):
      thinkingAgents.insert(agent)
    case .inferenceCompleted(let agent, _):
      thinkingAgents.remove(agent)
    default:
      handleOutputEvent(event)
    }
  }

  /// Handles score, vote, and other output-related events.
  private func handleOutputEvent(_ event: SimulationEvent) {
    switch event {
    case .scoreUpdate(let newScores):
      handleScoreUpdate(scores: newScores)
    case .elimination(let agent, let voteCount):
      handleElimination(agent: agent, voteCount: voteCount)
    case .assignment(let agent, let value):
      logEntries.append(LogEntry(kind: .assignment(agent: agent, value: value)))
    case .summary(let text):
      logEntries.append(LogEntry(kind: .summary(text: text)))
    case .voteResults(let votes, let tallies):
      logEntries.append(LogEntry(kind: .voteResults(votes: votes, tallies: tallies)))
    case .pairingResult(let agent1, let act1, let agent2, let act2):
      logEntries.append(
        LogEntry(
          kind: .pairingResult(
            agent1: agent1, action1: act1, agent2: agent2, action2: act2
          )))
    default:
      break
    }
  }

  private func handleRoundStarted(round: Int, total: Int) {
    currentRound = round
    totalRounds = total
    logEntries.append(LogEntry(kind: .roundStarted(round: round, totalRounds: total)))
  }

  private func handleRoundCompleted(round: Int, scores newScores: [String: Int]) {
    scores = newScores
    logEntries.append(LogEntry(kind: .roundCompleted(round: round, scores: newScores)))
  }

  private func handleAgentOutput(agent: String, output: TurnOutput, phaseType: PhaseType) {
    let filtered = contentFilter.filter(output)
    logEntries.append(
      LogEntry(
        kind: .agentOutput(
          agent: agent, output: filtered, phaseType: phaseType
        )))
    thinkingAgents.remove(agent)
    persistTurnRecord(agent: agent, output: output, phaseType: phaseType)
  }

  private func handleScoreUpdate(scores newScores: [String: Int]) {
    scores = newScores
    logEntries.append(LogEntry(kind: .scoreUpdate(scores: newScores)))
  }

  private func handleElimination(agent: String, voteCount: Int) {
    eliminated[agent] = true
    logEntries.append(LogEntry(kind: .elimination(agent: agent, voteCount: voteCount)))
  }

  // MARK: - Persistence

  private func createSimulationRecord(
    simId: String, scenario: Scenario, state: SimulationState
  ) async {
    do {
      let stateJSON = try JSONEncoder().encode(state)
      let record = SimulationRecord(
        id: simId,
        scenarioId: scenario.id,
        status: SimulationStatus.running.rawValue,
        currentRound: 0,
        currentPhaseIndex: 0,
        stateJSON: String(data: stateJSON, encoding: .utf8) ?? "{}",
        configJSON: nil,
        createdAt: Date(),
        updatedAt: Date()
      )
      try await offMain { [simulationRepository] in
        try simulationRepository.save(record)
      }
    } catch {
      print("⚠️ Failed to create simulation record: \(error)")
    }
  }

  private func startPersistenceConsumer() {
    let (stream, continuation) = AsyncStream<TurnRecord>.makeStream()
    persistenceContinuation = continuation
    let repo = turnRepository
    persistenceTask = Task.detached {
      for await record in stream {
        do {
          try repo.save(record)
        } catch {
          print("⚠️ Failed to persist turn: \(error)")
        }
      }
    }
  }

  private func persistTurnRecord(agent: String, output: TurnOutput, phaseType: PhaseType) {
    guard let simId = simulationId else { return }
    // Build record synchronously on MainActor so sequenceNumber is assigned in
    // event arrival order, then enqueue for serial DB write.
    do {
      let parsedJSON = try JSONEncoder().encode(output)
      let jsonString = String(data: parsedJSON, encoding: .utf8) ?? "{}"
      turnSequence += 1
      let record = TurnRecord(
        id: UUID().uuidString,
        simulationId: simId,
        roundNumber: currentRound,
        phaseType: phaseType.rawValue,
        agentName: agent,
        rawOutput: jsonString,
        parsedOutputJSON: jsonString,
        sequenceNumber: turnSequence,
        createdAt: Date()
      )
      persistenceContinuation?.yield(record)
    } catch {
      print("⚠️ Failed to encode turn output: \(error)")
    }
  }

  /// Mark the simulation as completed regardless of success or error outcome.
  /// Errors are recorded in `stateJSON`; `.paused` is reserved for user-initiated pause.
  private func finalizeSimulationStatus() async {
    guard let simId = simulationId else { return }
    let status: SimulationStatus = .completed
    do {
      try await offMain { [simulationRepository] in
        try simulationRepository.updateStatus(simId, status: status)
      }
    } catch {
      print("⚠️ Failed to update simulation status: \(error)")
    }
  }
}
