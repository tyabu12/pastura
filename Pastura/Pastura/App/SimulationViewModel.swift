// swiftlint:disable file_length
// Deliberately long: this view model is the hinge between the event-producing
// Engine, the SwiftUI view, persistence, content filtering, and the export
// pipeline. Splitting into extensions across files would require elevating
// many `private` repository/state members to internal, which trades the
// file-length limit for weaker encapsulation.
import Foundation
import os

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

/// Typing-animation speed tiers for simulation playback.
///
/// Rates are calibrated for Japanese text (higher information density per
/// character than English) and match contemporary Switch/PS visual-novel
/// conventions: x0.5 / x1 / x1.5 / Max. `x1` ≈ 30 char/sec feels natural for
/// mixed kana/kanji content; Ren'Py's 40 char/sec default is slightly too
/// fast on real devices.
///
/// Controls (1) per-character typing rate for agent outputs and (2) a small
/// delay between non-agentOutput events so phase/round transitions remain
/// perceptible. `.instant` skips both for developer-style rapid playback.
enum PlaybackSpeed: String, CaseIterable, Identifiable {
  case slow
  case normal
  case fast
  case instant

  var id: String { rawValue }

  /// Characters revealed per second during typing animation.
  /// `nil` means "render full text immediately" (`.instant`).
  var charsPerSecond: Double? {
    switch self {
    case .slow: 15
    case .normal: 30
    case .fast: 45
    case .instant: nil
    }
  }

  /// Delay inserted between consumed simulation events other than agent
  /// outputs (agent outputs are paced by the typing animation instead).
  /// Keeps round separators and phase labels on-screen long enough to read.
  var interEventDelayMs: Int {
    switch self {
    case .slow, .normal, .fast: 120
    case .instant: 0
    }
  }

  var label: String {
    switch self {
    case .slow: "x0.5"
    case .normal: "x1"
    case .fast: "x1.5"
    case .instant: "Max"
    }
  }
}

/// ViewModel for the live simulation execution screen.
///
/// Consumes `AsyncStream<SimulationEvent>` from `SimulationRunner`, applies
/// `ContentFilter`, persists turn records, and manages pause/resume + LLM lifecycle.
@Observable
final class SimulationViewModel {  // swiftlint:disable:this type_body_length
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
  // Internal `var` (not `private(set)`) because the BG continuation extension
  // in a separate file writes errorMessage from its switchToCPU/GPU error
  // catches. Cross-file extension access can't reach `private(set)`.
  var errorMessage: String?

  /// Most recent inference duration in seconds. `nil` until the first
  /// `.inferenceCompleted` event arrives.
  private(set) var lastInferenceDurationSeconds: Double?

  /// Weighted average generation throughput (Σtokens / Σseconds).
  /// Events with `tokenCount == nil` are excluded from both numerator and
  /// denominator — substituting zero tokens with their elapsed seconds
  /// would otherwise drag the average down for no reason. `nil` until at
  /// least one token-bearing event has been seen.
  var averageTokensPerSecond: Double? {
    guard totalCompletionTokens > 0, totalInferenceSeconds > 0 else { return nil }
    return Double(totalCompletionTokens) / totalInferenceSeconds
  }

  /// The log-entry id of the most recent `.agentOutput` event. Used by
  /// `AgentOutputRow` to decide whether to animate typing (only the latest
  /// row animates; earlier rows render full text immediately).
  private(set) var latestAgentOutputId: UUID?

  /// In-flight streaming snapshot for the currently-generating agent.
  ///
  /// Populated by ``SimulationEvent/agentOutputStream(agent:primary:thought:)``
  /// when the partial parser has confirmed a primary key's opening
  /// quote (i.e., `primary != nil`). `SimulationView` renders this as a
  /// live row below the committed log entries; the reveal animation in
  /// `AgentOutputRow` tracks the growing buffer at the user's chosen
  /// `charsPerSecond`.
  ///
  /// Cleared on ``SimulationEvent/agentOutput(agent:output:phaseType:)``
  /// (finalization — the committed `LogEntry` takes over display) and
  /// on ``SimulationEvent/inferenceStarted(agent:)`` (stale snapshot
  /// from a previous attempt should not leak across inferences).
  /// Only one is live at a time because the Engine runs inferences
  /// sequentially (ADR-002 §6).
  private(set) var streamingSnapshot: StreamingSnapshot?

  /// Entry IDs whose primary text was already revealed live via
  /// ``SimulationEvent/agentOutputStream(agent:primary:thought:)`` before
  /// the committing ``SimulationEvent/agentOutput(agent:output:phaseType:)``
  /// arrived. ``effectiveCharsPerSecond(forEntryId:)`` returns `nil` for
  /// these so `AgentOutputRow` snaps to full instead of retyping content
  /// the user already watched stream.
  ///
  /// Side-set rather than a flag on `LogEntry.Kind` because this is a
  /// display-only concern — `LogEntry.Kind` sits next to the persistence /
  /// export boundary and should not grow display-layer fields. Reset per
  /// `run()`; never persisted. See #133 for the longer-term redesign of
  /// the streaming display path.
  private(set) var prerevealedAgentOutputIds: Set<UUID> = []

  nonisolated struct StreamingSnapshot: Equatable, Sendable {
    let agent: String
    let primary: String
    let thought: String?
    let phaseType: PhaseType
  }

  // Running totals for weighted tok/s. See `averageTokensPerSecond`.
  private var totalCompletionTokens = 0
  private var totalInferenceSeconds: Double = 0
  // Default ON: inner thoughts provide interpretive context without drawbacks.
  var showAllThoughts = true
  var speed: PlaybackSpeed = .normal

  /// Chars-per-second to use for the committed `AgentOutputRow` of `entryId`,
  /// or `nil` when the row must not animate.
  ///
  /// Centralising this decision here (rather than inlining the conditional
  /// in `SimulationView`) keeps the regression from #132-QA — committed
  /// rows retyping text the user just watched stream — pinned at the VM
  /// boundary where it can be unit-tested. The view has one call site,
  /// and any future code that renders an `.agentOutput` entry must go
  /// through this helper to get the display timing right.
  ///
  /// Returns `nil` when:
  /// - the entry was pre-revealed via streaming (`prerevealedAgentOutputIds`),
  ///   or
  /// - the user has chosen `.instant` playback (`speed.charsPerSecond == nil`).
  func effectiveCharsPerSecond(forEntryId entryId: UUID) -> Double? {
    if prerevealedAgentOutputIds.contains(entryId) { return nil }
    return speed.charsPerSecond
  }

  /// Read-only view of the runner's pause state. Views observe this to drive
  /// the pause-button label and "Paused" pill. **Mutation must go through
  /// ``pauseSimulation(reason:)`` / ``resumeSimulation()``** — those methods
  /// co-manage `runner.isPaused` and `suspendController` so an in-flight
  /// generate is interrupted cooperatively rather than waiting for the next
  /// phase boundary (ADR-003 §10 invariant 6).
  var isPaused: Bool { runner.isPaused }

  // MARK: - Background continuation state

  /// Whether the user has enabled background simulation continuation.
  /// The toggle only takes effect if `canEnableBackgroundContinuation` is true.
  /// Set by the BG continuation extension (in a separate file).
  var isBackgroundContinuationEnabled = false

  /// Whether the most recent BG task activation callback has fired for the
  /// current toggle cycle. Set by `handleBackgroundActivation` (before its
  /// guards so the one-shot scheduled request is considered consumed even if
  /// the VM is no longer running). Reset on each `enableBackgroundContinuation`
  /// success and on `disableBackgroundContinuation`.
  ///
  /// Gates the toggle-disarm path in `handleScenePhaseForeground`: a transient
  /// `.inactive → .active` (Control Center pull, notification drawer) must not
  /// disarm the user's armed toggle — only a real BG activation does.
  /// Plain `var` (not `private(set)`) because the BG continuation extension
  /// in a separate file writes it.
  var didActivateBGTask = false

  /// Mirror of the app's scene-phase (`true` while `scenePhase == .background`).
  /// Updated by `SimulationView`'s `.onChange(of: scenePhase)` observer BEFORE
  /// it dispatches the FG/BG handler Tasks — so any queued BG expiration
  /// callback running on the MainActor afterwards sees the fresh value.
  ///
  /// Gates `handleBackgroundExpiration`: when the system fires the expiration
  /// closure during/after a FG return, the pause it would apply is stale and
  /// would leave the user stranded with `runner.isPaused = true` plus a
  /// misleading "Background time exceeded" log after they've already returned.
  var isAppBackgrounded = false

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
  private let codePhaseEventRepository: (any CodePhaseEventRepository)?
  private let scenarioRepository: (any ScenarioRepository)?
  // Accessed from the BG continuation extension in SimulationViewModel+Background.swift
  let backgroundManager: BackgroundSimulationManager?
  // Lifecycle logger — accessed from the +Background extension. Use `info` for
  // routine state transitions and `error` for unexpected paths so device logs
  // stay readable.
  let lifecycleLogger = Logger(subsystem: "com.pastura", category: "SimulationVM")
  // Non-private so `@testable import` can seed persistence without invoking `run()`.
  internal var simulationId: String?

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

  // Parallel queue for code-phase events. Drained alongside the turns queue
  // before `.completed` status is persisted so exporters can fetch complete
  // data immediately after `run()` returns.
  private var codePhasePersistenceContinuation: AsyncStream<CodePhaseEventRecord>.Continuation?
  private var codePhasePersistenceTask: Task<Void, Never>?

  /// Per-simulation sequence counter for deterministic ordering of BOTH
  /// `TurnRecord` (agent output) and `CodePhaseEventRecord`. Each event is
  /// routed to exactly one stream and increments this counter exactly once
  /// on MainActor — a single yield per event guarantees strict total order
  /// for merge-sort at export time.
  ///
  /// TODO(resume): when pause/resume lands, re-initialize from
  /// `MAX(sequenceNumber)` across both tables so resumed runs do not collide
  /// with existing persisted rows.
  private var turnSequence = 0

  /// The phase currently executing, tracked via `.phaseStarted` events.
  /// `.summary` has multiple emitters (`SummarizeHandler` and scoring logics
  /// like `wordwolf_judge` that live inside `ScoreCalcHandler`), so the
  /// phaseType column of the persisted `CodePhaseEventRecord` must come from
  /// the engine's execution context rather than the event shape.
  private var currentPhaseType: PhaseType?

  init(
    runner: SimulationRunner = SimulationRunner(),
    contentFilter: ContentFilter = ContentFilter(),
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository,
    codePhaseEventRepository: (any CodePhaseEventRepository)? = nil,
    scenarioRepository: (any ScenarioRepository)? = nil,
    backgroundManager: BackgroundSimulationManager? = nil
  ) {
    self.runner = runner
    self.contentFilter = contentFilter
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
    self.codePhaseEventRepository = codePhaseEventRepository
    self.scenarioRepository = scenarioRepository
    self.backgroundManager = backgroundManager
  }

  // MARK: - Simulation Lifecycle

  /// Cancels a running simulation.
  /// Task cancellation terminates the runner's AsyncStream; the `for await`
  /// loop exits and post-loop cleanup runs.
  /// `caller` defaults to the source-location `#function` of the caller, so logs
  /// immediately reveal which path triggered the cancel — invaluable for
  /// distinguishing memory-warning vs reload-failure vs explicit user cancel.
  /// Pauses the simulation, interrupting any in-flight `generate` cooperatively.
  ///
  /// Co-manages `runner.isPaused` (so the runner waits at the next phase
  /// boundary) and `suspendController` (so the in-flight generate exits within
  /// milliseconds rather than running to completion). Pair with
  /// ``resumeSimulation()``.
  ///
  /// - Parameter reason: Optional message appended to the log so the user
  ///   knows *why* they were paused (e.g., memoryWarning). Pass `nil` for
  ///   user-initiated pauses where no log entry is needed.
  func pauseSimulation(reason: String? = nil) {
    // Defensive: the BG-task expiration callback may fire after run() has
    // already exited (e.g., user cancelled, then iOS expired the BG task
    // shortly after). Don't append spurious log entries or mutate runner
    // state in that window.
    guard isRunning else {
      lifecycleLogger.info(
        "pauseSimulation: skipped (not running). reason=\(reason ?? "user", privacy: .public)"
      )
      return
    }
    lifecycleLogger.info(
      "pauseSimulation: reason=\(reason ?? "user", privacy: .public), isPaused=\(self.isPaused)"
    )
    if let reason {
      logEntries.append(LogEntry(kind: .summary(text: reason)))
    }
    runner.isPaused = true
    suspendController?.requestSuspend()
  }

  /// Resumes a paused simulation. Symmetric counterpart to
  /// ``pauseSimulation(reason:)`` — wakes any parked generate and unblocks
  /// the runner's phase-boundary checkpoint.
  func resumeSimulation() {
    lifecycleLogger.info("resumeSimulation: isPaused=\(self.isPaused)")
    runner.isPaused = false
    suspendController?.resume()
  }

  func cancelSimulation(caller: String = #function) {
    lifecycleLogger.info(
      "cancelSimulation called by \(caller, privacy: .public): isRunning=\(self.isRunning), isOnCPU=\(self.isOnCPU), isReloadingModel=\(self.isReloadingModel)"
    )
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
  func run(scenario: Scenario, llm: any LLMService) async {  // swiftlint:disable:this function_body_length
    currentLLM = llm
    isRunning = true
    isCompleted = false
    isCancelled = false
    errorMessage = nil
    logEntries = []
    // Latent: a second `run()` on the same VM instance would otherwise inherit
    // these from the previous simulation — `latestAgentOutputId` points at a
    // UUID no longer in `logEntries`, and `streamingSnapshot` could render a
    // stale in-flight row under a brand-new scenario.
    latestAgentOutputId = nil
    streamingSnapshot = nil
    prerevealedAgentOutputIds = []
    scores = Dictionary(uniqueKeysWithValues: scenario.personas.map { ($0.name, 0) })
    eliminated = Dictionary(uniqueKeysWithValues: scenario.personas.map { ($0.name, false) })
    totalRounds = scenario.rounds

    // Create simulation record
    let simId = UUID().uuidString
    simulationId = simId
    let initialState = SimulationState.initial(for: scenario)
    await createSimulationRecord(
      simId: simId, scenario: scenario, state: initialState, llm: llm)

    turnSequence = 0

    // Attach BEFORE loadModel so scene-phase handlers can signal suspend as
    // soon as run() is in flight.
    let controller = SuspendController()
    suspendController = controller
    await llm.attachSuspendController(controller)

    // Start both persistence consumers before any events can arrive.
    startPersistenceConsumer()
    startCodePhasePersistenceConsumer()
    lifecycleLogger.info("run() entered: simId=\(simId)")
    // Guarantee cleanup in ALL exit paths (LLM load failure, cancellation, etc.)
    defer {
      lifecycleLogger.info(
        "run() defer: isCompleted=\(self.isCompleted), isCancelled=\(self.isCancelled), errorMessage=\(self.errorMessage ?? "nil")"
      )
      // Release any parked generate before tearing down state. Idempotent.
      controller.resume()
      persistenceContinuation?.finish()
      codePhasePersistenceContinuation?.finish()
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
      await finalizeSimulationStatus(.failed)
      return
    }

    // Consume event stream. Agent outputs are paced by the per-row typing
    // animation in AgentOutputRow; other events (phase/round separators,
    // code-phase results) get a small fixed delay so they stay on-screen
    // long enough to read. `.instant` skips both.
    for await event in runner.run(
      scenario: scenario, llm: llm, suspendController: controller
    ) {
      if case .agentOutput = event {
        // no inter-event sleep — typing animation handles pacing
      } else if speed.interEventDelayMs > 0 {
        try? await Task.sleep(for: .milliseconds(speed.interEventDelayMs))
      }

      handleEvent(event, scenario: scenario)
    }

    // Drain BOTH persistence queues before marking simulation as completed.
    // `fetchExportPayload` guards on `.completed`, so unflushed writes would
    // race the export. finish() is idempotent; defer also calls it for
    // early-return paths.
    persistenceContinuation?.finish()
    codePhasePersistenceContinuation?.finish()
    await persistenceTask?.value
    await codePhasePersistenceTask?.value

    // Cleanup
    try? await llm.unloadModel()

    // Pick the terminal status: cancellation intent trumps normal end, but an
    // error (event-pipeline or persistence) beats both — a broken run is objectively
    // failed even if the user also pressed cancel.
    let terminal: SimulationStatus
    if errorMessage != nil {
      terminal = .failed
    } else if isCancelled {
      terminal = .cancelled
    } else {
      terminal = .completed
    }
    await finalizeSimulationStatus(terminal)
  }

  // MARK: - Event Handling

  // internal (not private) to allow direct unit testing via @testable import
  func handleEvent(_ event: SimulationEvent, scenario: Scenario) {  // swiftlint:disable:this cyclomatic_complexity

    switch event {
    case .roundStarted(let round, let total):
      handleRoundStarted(round: round, total: total)
    case .roundCompleted(let round, let newScores):
      handleRoundCompleted(round: round, scores: newScores)
    case .phaseStarted(let phaseType, _):
      currentPhaseType = phaseType
      logEntries.append(LogEntry(kind: .phaseStarted(phaseType: phaseType)))
    case .phaseCompleted, .simulationPaused, .conditionalEvaluated:
      // No-op — `.simulationPaused` is a runner-side acknowledgement of the
      // user-initiated pause flow; the UI already reflects `isPaused` set
      // synchronously by the pause button. Background-driven suspend uses
      // the SuspendController path instead.
      //
      // `.conditionalEvaluated` is visible via the bracketing
      // `.phaseStarted(.conditional, _)` + inner sub-phase events; UI
      // surfacing of the condition/result pair is deferred, and persistence
      // waits on the follow-up TurnRecord-phase-path migration.
      break
    case .agentOutput(let agent, let output, let phaseType):
      handleAgentOutput(agent: agent, output: output, phaseType: phaseType)
    case .agentOutputStream(let agent, let primary, let thought):
      handleAgentOutputStream(agent: agent, primary: primary, thought: thought)
    case .simulationCompleted:
      isCompleted = true
    case .error(let simError):
      errorMessage = "\(simError)"
      logEntries.append(LogEntry(kind: .error("\(simError)")))
    case .inferenceStarted(let agent):
      thinkingAgents.insert(agent)
      // A new inference starts: any leftover snapshot from a previous
      // attempt (parse retry, different agent) must not linger in the UI.
      streamingSnapshot = nil
    case .inferenceCompleted(let agent, let seconds, let tokens):
      thinkingAgents.remove(agent)
      handleInferenceCompleted(durationSeconds: seconds, tokenCount: tokens)
    default:
      handleOutputEvent(event)
    }
  }

  /// Handles score, vote, and other code-phase result events. Each branch
  /// updates UI state AND persists a `CodePhaseEventRecord` so exports can
  /// reconstruct per-phase outcomes.
  ///
  /// The persisted `phaseType` column uses `currentPhaseType` (tracked from
  /// `.phaseStarted`) with a per-event fallback. This is essential for
  /// `.summary`, which fires from both `SummarizeHandler` and scoring logics
  /// like `wordwolf_judge` inside `ScoreCalcHandler` — hard-coding would
  /// bucket the judge verdict into the wrong phase in exports.
  private func handleOutputEvent(_ event: SimulationEvent) {
    switch event {
    case .scoreUpdate(let newScores):
      handleScoreUpdate(scores: newScores)
      persistCodePhaseEvent(
        phaseType: currentPhaseType?.rawValue ?? PhaseType.scoreCalc.rawValue,
        payload: .scoreUpdate(scores: newScores))
    case .elimination(let agent, let voteCount):
      handleElimination(agent: agent, voteCount: voteCount)
      persistCodePhaseEvent(
        phaseType: currentPhaseType?.rawValue ?? PhaseType.eliminate.rawValue,
        payload: .elimination(agent: agent, voteCount: voteCount))
    case .assignment(let agent, let value):
      logEntries.append(LogEntry(kind: .assignment(agent: agent, value: value)))
      persistCodePhaseEvent(
        phaseType: currentPhaseType?.rawValue ?? PhaseType.assign.rawValue,
        payload: .assignment(agent: agent, value: value))
    case .summary(let text):
      logEntries.append(LogEntry(kind: .summary(text: text)))
      // `.summary` also fires for validator warnings (before the first round
      // starts, currentRound == 0) and early-termination (after the round
      // loop exits). Export intentionally drops pre-round warnings — they
      // are diagnostic, not part of the scenario's narrative.
      if currentRound > 0 {
        persistCodePhaseEvent(
          phaseType: currentPhaseType?.rawValue ?? PhaseType.summarize.rawValue,
          payload: .summary(text: text))
      }
    case .voteResults(let votes, let tallies):
      logEntries.append(LogEntry(kind: .voteResults(votes: votes, tallies: tallies)))
      persistCodePhaseEvent(
        phaseType: currentPhaseType?.rawValue ?? PhaseType.vote.rawValue,
        payload: .voteResults(votes: votes, tallies: tallies))
    case .pairingResult(let agent1, let act1, let agent2, let act2):
      logEntries.append(
        LogEntry(
          kind: .pairingResult(
            agent1: agent1, action1: act1, agent2: agent2, action2: act2
          )))
      persistCodePhaseEvent(
        phaseType: currentPhaseType?.rawValue ?? PhaseType.choose.rawValue,
        payload: .pairingResult(
          agent1: agent1, action1: act1, agent2: agent2, action2: act2))
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
    // Divergence telemetry: compare the last streamed snapshot against
    // the canonical parser result for the same inference. A mismatch
    // here means the partial extractor showed the user something that
    // the canonical parse later contradicted — exactly the failure
    // mode the critic flagged. Debug-level so it stays available for
    // future investigation without polluting production logs.
    if let snapshot = streamingSnapshot, snapshot.agent == agent {
      let canonicalPrimary = filtered.primaryText(for: phaseType) ?? ""
      if !canonicalPrimary.hasPrefix(snapshot.primary) {
        lifecycleLogger.debug(
          "stream divergence: agent=\(agent, privacy: .public), snapshot primary \(snapshot.primary.prefix(40), privacy: .public) is not a prefix of canonical \(canonicalPrimary.prefix(40), privacy: .public)"
        )
      }
    }
    // If snapshot was active for this agent the user has already watched
    // the primary stream live, so the committed AgentOutputRow must not
    // retype it (see `effectiveCharsPerSecond(forEntryId:)`).
    //
    // Note: `contentFilter.filter(output)` above may rewrite the primary,
    // so the committed snap can differ from what streamed. Acceptable:
    // filter rewrites are rare and already surface via divergence
    // telemetry; any transition UX on that edge belongs to the #133
    // streaming-display redesign, not here.
    let wasStreamed = streamingSnapshot?.agent == agent
    streamingSnapshot = nil
    let entry = LogEntry(
      kind: .agentOutput(agent: agent, output: filtered, phaseType: phaseType))
    logEntries.append(entry)
    // Track the newest agentOutput so AgentOutputRow can gate the typing
    // animation to only the latest row — older rows snap to full text when
    // this id flips.
    latestAgentOutputId = entry.id
    if wasStreamed { prerevealedAgentOutputIds.insert(entry.id) }
    thinkingAgents.remove(agent)
    persistTurnRecord(agent: agent, output: output, phaseType: phaseType)
  }

  /// Update the in-flight streaming snapshot from a partial-parser
  /// emission. `nil` primary means the primary key's opening quote has
  /// not arrived yet — we keep `thinkingAgents` populated so the UI
  /// continues to show the "thinking" indicator.
  ///
  /// Gated by ``FeatureFlags/realtimeStreamingEnabled``. When disabled,
  /// events are silently dropped so the UI falls back to the
  /// pre-streaming flow (thinking indicator → committed row at
  /// `.agentOutput`). LLMCaller still produces the events but they
  /// become no-ops here; the cost is negligible.
  private func handleAgentOutputStream(
    agent: String, primary: String?, thought: String?
  ) {
    guard FeatureFlags.realtimeStreamingEnabled else { return }
    guard let primary else { return }
    // Defensive: drop the event if we somehow see a stream before
    // `.phaseStarted`. The snapshot needs a correct `phaseType` so
    // `AgentOutputRow.primaryText` pulls the right fields on the
    // committed row; a silent fallback to `.speakAll` would hide the
    // ordering bug. Symmetric with the `primary == nil` drop above —
    // if any required precondition is missing, defer to `.agentOutput`
    // for display instead of rendering a partial row under the wrong
    // phase.
    guard let phaseType = currentPhaseType else { return }
    // Past the opening quote — the streaming row now has real content.
    // Remove the "thinking" indicator (the live row takes over display).
    thinkingAgents.remove(agent)
    // Match the filtering that `handleAgentOutput` applies at commit — the
    // in-flight snapshot is a user-visible display surface, so it must
    // pass through ContentFilter for App Store compliance (policy owner:
    // ADR-005 §5). A partial prefix of a blocked pattern still displays
    // raw until the pattern completes (e.g. "fu" then "fuck" → "***");
    // that residual leakage is an accepted risk per ADR-005 §5.3, with
    // the eventual mechanical fix (if any) riding on the streaming-
    // display refactor tracked in #133.
    streamingSnapshot = StreamingSnapshot(
      agent: agent,
      primary: contentFilter.filter(primary),
      thought: thought.map { contentFilter.filter($0) },
      phaseType: phaseType
    )
  }

  private func handleScoreUpdate(scores newScores: [String: Int]) {
    scores = newScores
    logEntries.append(LogEntry(kind: .scoreUpdate(scores: newScores)))
  }

  private func handleElimination(agent: String, voteCount: Int) {
    eliminated[agent] = true
    logEntries.append(LogEntry(kind: .elimination(agent: agent, voteCount: voteCount)))
  }

  private func handleInferenceCompleted(durationSeconds: Double, tokenCount: Int?) {
    lastInferenceDurationSeconds = durationSeconds
    // Only accumulate when tokens are known. Adding the seconds of a
    // nil-token event without its tokens would drag tok/s below reality.
    if let tokenCount, tokenCount > 0 {
      totalCompletionTokens += tokenCount
      totalInferenceSeconds += durationSeconds
    }
  }

  // MARK: - Persistence

  private func createSimulationRecord(
    simId: String, scenario: Scenario, state: SimulationState, llm: any LLMService
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
        updatedAt: Date(),
        modelIdentifier: llm.modelIdentifier,
        llmBackend: llm.backendIdentifier
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

  private func startCodePhasePersistenceConsumer() {
    // If no repository was injected, skip starting the consumer — yields
    // from `persistCodePhaseEvent` become no-ops because the continuation
    // stays nil. This keeps existing call sites (pre-#92 constructors) working.
    guard let codePhaseRepo = codePhaseEventRepository else { return }
    let (stream, continuation) = AsyncStream<CodePhaseEventRecord>.makeStream()
    codePhasePersistenceContinuation = continuation
    codePhasePersistenceTask = Task.detached {
      for await record in stream {
        do {
          try codePhaseRepo.save(record)
        } catch {
          print("⚠️ Failed to persist code-phase event: \(error)")
        }
      }
    }
  }

  private func persistCodePhaseEvent(
    phaseType: String, payload: CodePhaseEventPayload
  ) {
    guard let simId = simulationId else { return }
    guard let continuation = codePhasePersistenceContinuation else { return }
    do {
      let data = try JSONEncoder().encode(payload)
      // JSONEncoder always produces valid UTF-8, so the conversion can't fail
      // in practice. Bail out instead of falling back to "{}" so a bogus
      // payload does not reserve a sequenceNumber slot.
      guard let jsonString = String(data: data, encoding: .utf8) else {
        print("⚠️ Failed to stringify code-phase payload JSON")
        return
      }
      turnSequence += 1
      let record = CodePhaseEventRecord(
        id: UUID().uuidString,
        simulationId: simId,
        roundNumber: currentRound,
        phaseType: phaseType,
        sequenceNumber: turnSequence,
        payloadJSON: jsonString,
        createdAt: Date()
      )
      continuation.yield(record)
    } catch {
      print("⚠️ Failed to encode code-phase payload: \(error)")
    }
  }

  // MARK: - Test Seams

  /// Initializes persistence without invoking `run()`, so unit tests can
  /// exercise `handleEvent` directly and assert DB contents. Pair with
  /// `finishPersistenceForTest()` to drain both queues before assertions.
  internal func beginPersistenceForTest(simulationId: String) {
    self.simulationId = simulationId
    turnSequence = 0
    startPersistenceConsumer()
    startCodePhasePersistenceConsumer()
  }

  /// Drains both persistence queues synchronously with the caller. Use after
  /// `beginPersistenceForTest(simulationId:)` and a series of `handleEvent`
  /// calls before querying the DB.
  internal func finishPersistenceForTest() async {
    persistenceContinuation?.finish()
    codePhasePersistenceContinuation?.finish()
    await persistenceTask?.value
    await codePhasePersistenceTask?.value
  }

  // MARK: - Export

  private struct ExportRecords: Sendable {
    let simulation: SimulationRecord
    let scenario: ScenarioRecord
    let turns: [TurnRecord]
    let codePhaseEvents: [CodePhaseEventRecord]
  }

  /// Fetches the current simulation's records and renders them as a Markdown
  /// export payload. Returns `nil` when the simulation is not started, not
  /// `.completed`, or when `scenarioRepository` was not injected.
  func fetchExportPayload(
    exportEnvironment: ResultMarkdownExporter.ExportEnvironment
  ) async throws -> ResultMarkdownExporter.ExportedResult? {
    guard let simId = simulationId, let scenarioRepository else { return nil }
    let simulationRepository = self.simulationRepository
    let turnRepository = self.turnRepository
    let codePhaseEventRepository = self.codePhaseEventRepository

    let records: ExportRecords? = try await offMain {
      guard
        let sim = try simulationRepository.fetchById(simId),
        let scenario = try scenarioRepository.fetchById(sim.scenarioId)
      else {
        return nil
      }
      let turns = try turnRepository.fetchBySimulationId(simId)
      let codeEvents = try codePhaseEventRepository?.fetchBySimulationId(simId) ?? []
      return ExportRecords(
        simulation: sim, scenario: scenario,
        turns: turns, codePhaseEvents: codeEvents)
    }

    guard let records, records.simulation.simulationStatus == .completed else { return nil }

    // Parse personas from the scenario YAML. Exports stay usable even when
    // the YAML fails to parse — the Final Scores / Roster Status section is
    // simply omitted rather than aborting the whole export.
    let personas: [String] = {
      guard
        let scenario = try? ScenarioLoader().load(yaml: records.scenario.yamlDefinition)
      else { return [] }
      return scenario.personas.map(\.name)
    }()

    let state = decodeState(from: records.simulation) ?? SimulationState()
    let exporter = ResultMarkdownExporter(
      contentFilter: contentFilter,
      environment: exportEnvironment)
    return try exporter.export(
      ResultMarkdownExporter.Input(
        simulation: records.simulation,
        scenario: records.scenario,
        turns: records.turns,
        codePhaseEvents: records.codePhaseEvents,
        personas: personas,
        state: state))
  }

  private func decodeState(from record: SimulationRecord) -> SimulationState? {
    guard let data = record.stateJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SimulationState.self, from: data)
  }

  /// Persist the terminal status decided by the caller. `.paused` is NOT passed
  /// here — it is reserved for the pause/resume flow in `runner.isPaused`.
  private func finalizeSimulationStatus(_ status: SimulationStatus) async {
    guard let simId = simulationId else { return }
    do {
      try await offMain { [simulationRepository] in
        try simulationRepository.updateStatus(simId, status: status)
      }
    } catch {
      print("⚠️ Failed to update simulation status: \(error)")
    }
  }
}
