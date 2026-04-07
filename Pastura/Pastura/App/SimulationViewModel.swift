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
  private(set) var errorMessage: String?
  var showDebugOutput = false
  var speed: PlaybackSpeed = .normal

  var isPaused: Bool {
    get { runner.isPaused }
    set { runner.isPaused = newValue }
  }

  // MARK: - Dependencies

  private let runner: SimulationRunner
  private let contentFilter: ContentFilter
  private let simulationRepository: any SimulationRepository
  private let turnRepository: any TurnRepository
  private var simulationId: String?

  init(
    runner: SimulationRunner = SimulationRunner(),
    contentFilter: ContentFilter = ContentFilter(),
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository
  ) {
    self.runner = runner
    self.contentFilter = contentFilter
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
  }

  // MARK: - Simulation Lifecycle

  /// Starts the simulation, consuming events and persisting results.
  func run(scenario: Scenario, llm: any LLMService) async {
    isRunning = true
    isCompleted = false
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

    // Load LLM model
    do {
      try await llm.loadModel()
    } catch {
      errorMessage = "Failed to load LLM: \(error.localizedDescription)"
      isRunning = false
      return
    }

    // Consume event stream
    for await event in runner.run(scenario: scenario, llm: llm) {
      // Apply speed delay (for non-instant playback)
      if speed != .fastest {
        try? await Task.sleep(for: .milliseconds(Int(200 * speed.rawValue)))
      }

      handleEvent(event, scenario: scenario)
    }

    // Cleanup
    try? await llm.unloadModel()
    await updateSimulationStatus(completed: errorMessage == nil)
    isRunning = false
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

  // internal (not private) to allow direct unit testing via @testable import
  /// Handles score, vote, and other output-related events.
  func handleOutputEvent(_ event: SimulationEvent) {
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

  private func persistTurnRecord(agent: String, output: TurnOutput, phaseType: PhaseType) {
    guard let simId = simulationId else { return }
    Task.detached { [turnRepository, currentRound] in
      do {
        let parsedJSON = try JSONEncoder().encode(output)
        let record = TurnRecord(
          id: UUID().uuidString,
          simulationId: simId,
          roundNumber: currentRound,
          phaseType: phaseType.rawValue,
          agentName: agent,
          rawOutput: String(data: parsedJSON, encoding: .utf8) ?? "{}",
          parsedOutputJSON: String(data: parsedJSON, encoding: .utf8) ?? "{}",
          createdAt: Date()
        )
        try turnRepository.save(record)
      } catch {
        print("⚠️ Failed to persist turn: \(error)")
      }
    }
  }

  private func updateSimulationStatus(completed: Bool) async {
    guard let simId = simulationId else { return }
    // Use .completed for both success and error — the error is recorded in
    // stateJSON. .paused is reserved for user-initiated pause with intent to resume.
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
