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
    /// The round's shared お題 assigned to every agent (`assign` target: all,
    /// #939). One line, no agent attribution.
    case sharedAssignment(value: String)
    case summary(text: String)
    /// Live commentary from a `narrate` phase (#909). Distinct from `.summary`
    /// so it can carry commentator (📺) styling. The carried text is already
    /// `ContentFilter`-rewritten at the VM boundary (see `handleOutputEvent`'s
    /// `.narration` arm) — unlike `.summary`, whose deterministic text is
    /// rendered raw — because narration is free LLM prose about the agents.
    case narration(text: String)
    case voteResults(votes: [String: String], tallies: [String: Int])
    case pairingResult(agent1: String, action1: String, agent2: String, action2: String)
    /// Result of an `event_inject` phase. `event == nil` means the
    /// probability roll missed; the live log renders this as a muted "no
    /// event this time" line so users can observe the dice did roll.
    case eventInjected(event: String?)
    /// A declaration/action contradiction detected at choose-phase completion
    /// (#916): `agent`'s `declared_intent` was contradicted by every one of
    /// their choose actions this round. Rendered as the 🃏 reveal line.
    case contradictionRevealed(agent: String)
    /// A degraded (skipped) LLM turn — ADR-021 D5. One live-log line per
    /// skip, narrating *which* agent's turn was omitted and *where*
    /// (the phase). Live-only: the durable post-hoc signal is the
    /// aggregate `degradedTurnCount` (D6), not a per-line persistence.
    /// The engine event's `cause` (English diagnostic) is deliberately
    /// NOT carried here — the App renders its own localized narration
    /// from `agent` + `phaseType`.
    case turnSkipped(agent: String, phaseType: PhaseType)
    case error(String)
  }
}

/// Presentation model for the viewer-prediction sheet (#915), wrapping the
/// question and choosable roster with a stable identity for `.sheet(item:)`.
struct ViewerPredictionPrompt: Identifiable {
  let id = UUID()
  let question: ViewerPredictionLogic.Question
  let candidates: [String]
}

/// The scored result of this run's viewer prediction (#915), shown alongside
/// the final result card. `streak` is the consecutive-hit count as of this run.
struct PredictionOutcome: Equatable, Sendable {
  let isHit: Bool
  let streak: Int
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
  /// Latest vote-phase tallies (target name → votes received), from the most
  /// recent `.voteResults` event. Feeds the final-ranking card's ranking of a
  /// vote-only ("popularity vote") scenario that eliminates nobody (#868).
  private(set) var voteResults: [String: Int] = [:]
  /// Per-agent vote count captured at the moment of each agent's elimination,
  /// from `.elimination` events. Round-correct — an agent eliminated in an
  /// earlier round keeps its own count, which a last-wins tally would drop.
  /// Feeds the final-ranking card's survival framing (#868).
  private(set) var eliminationVotes: [String: Int] = [:]
  private(set) var currentRound = 0
  private(set) var totalRounds = 0
  private(set) var thinkingAgents: Set<String> = []
  private(set) var isRunning = false
  private(set) var isCompleted = false
  private(set) var isCancelled = false
  /// `true` once `pauseSimulation` has persisted a `.paused` status for the
  /// current run. Gates the `run()` terminal ladder so a run torn down while
  /// explicitly paused (e.g. user navigated away) keeps its resumable
  /// `.paused` row instead of being overwritten with `.completed`/`.failed`.
  /// Cleared on a fresh `run()`, on `resumeSimulation`, and on
  /// `cancelSimulation`. Invariant: `didPersistPaused` is only ever observed
  /// `true` at run exit when the runner was still parked at a pause boundary —
  /// a resumed run clears it before it can complete.
  private var didPersistPaused = false
  /// `true` while the current run was started via ``resume(record:scenario:llm:)``
  /// rather than a fresh ``run(scenario:llm:)``. Gates two resume-specific
  /// behaviors: the `finalizeRun` terminal ladder leaves a mid-flight-torn-down
  /// resumed run at `.paused` (resumable) instead of `.completed`, and the
  /// `.error` handler suppresses a teardown `.cancelled` even when
  /// `didPersistPaused` is false (a resumed run that was never re-paused). Reset
  /// to `false` per run by `prepareRunInfrastructure`; set `true` by `resume`.
  private var isResumedRun = false
  /// Serializes status-column writes (`.paused` / `.running`) in call order.
  /// `pauseSimulation` and `resumeSimulation` each enqueue onto this chain so a
  /// rapid pause→resume cannot land `.paused` *after* `.running` (independent
  /// unstructured Tasks have no ordering guarantee). MainActor-isolated, so the
  /// assignment order in `enqueueStatusWrite` equals the call order.
  private var statusWriteTask: Task<Void, Never>?
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

  /// Whether the current ``latestAgentOutputId`` row has already finished its
  /// typewriter reveal. Load-bearing for the ADR-017 Phase B "keep running"
  /// adopt path: when a parked run is re-projected into a fresh `SimulationView`
  /// (`SimulationSession.adoptIfMatching`), the row's per-view `visibleChars`
  /// `@State` resets to its handoff seed and would re-type — even though the
  /// user already watched it reveal. This flag lives on the surviving VM so the
  /// re-projection restores it: ``effectiveCharsPerSecond(forEntryId:)`` returns
  /// `nil` (static) for a completed latest row. Reset to `false` when a newer
  /// row commits (it becomes the latest and hasn't revealed yet) and per `run()`.
  private(set) var latestRowRevealCompleted = false

  /// Grapheme length of the most recently committed `.agentOutput` primary
  /// text (inner-thought excluded), captured in
  /// ``handleAgentOutput(agent:output:phaseType:)``. Drives the post-dispatch
  /// reading pause (``holdAfterAgentOutput()``) via
  /// ``PlaybackSpeed/readingDwell(displayLength:)``. Display-only — never
  /// persisted; read only in the same consume-loop iteration it is written,
  /// so it needs no cross-run reset.
  private(set) var lastAgentOutputDisplayLength: Int = 0

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

  /// Per-entry reveal-handoff seed: for a committed `.agentOutput` whose
  /// primary streamed live, the streaming row's `visibleChars` position at
  /// commit time. ``AgentOutputRow`` seeds its reveal from this value (via
  /// ``handoffSeed(forEntryId:)``) and CONTINUES typing at cps
  /// from there — instead of snapping to full — so the unrevealed tail and
  /// `inner_thought` keep animating after commit (bug 2 / reveal-position
  /// handoff). Entries absent from the map (non-streamed rows, or a streamed
  /// row whose reveal had not started) seed at 0 and animate from the start.
  ///
  /// Side-set rather than a flag on `LogEntry.Kind` because this is a
  /// display-only concern — `LogEntry.Kind` sits next to the persistence /
  /// export boundary and should not grow display-layer fields. Reset per
  /// `run()`; never persisted. See #133 for the longer-term redesign of
  /// the streaming display path.
  private(set) var streamingHandoffChars: [UUID: Int] = [:]

  /// The in-flight streaming row's latest reveal position (`visibleChars`),
  /// reported via ``reportStreamingReveal(_:)`` on every reveal tick. At
  /// commit it becomes the committed row's handoff seed
  /// (``streamingHandoffChars``).
  ///
  /// `@ObservationIgnored`: written on every per-character tick of the live
  /// row, and no view reads it, so routing it through `@Observable` would be
  /// pure invalidation churn. Reset per run, per inference
  /// (``SimulationEvent/inferenceStarted(agent:)``), and at each commit
  /// boundary so one agent's reveal can never seed another agent's row.
  @ObservationIgnored private var streamingRevealedChars: Int = 0

  /// Reveal inputs of the just-committed row (handoff seed + decorated
  /// primary / thought segments), captured in
  /// ``handleAgentOutput(agent:output:phaseType:)`` so
  /// ``holdAfterAgentOutput(script:)`` can size the typing-synced hold via
  /// ``remainingTypingDurationMs(seed:primary:thought:charsPerSecond:)``.
  /// Display-only; read in the same consume-loop iteration it is written.
  @ObservationIgnored private var lastAgentOutputReveal: AgentOutputReveal?

  /// The handoff seed + decorated reveal segments of a committed row. See
  /// ``lastAgentOutputReveal``.
  private struct AgentOutputReveal {
    let seed: Int
    let primary: String
    let thought: String
  }

  nonisolated struct StreamingSnapshot: Equatable, Sendable {
    let agent: String
    let primary: String
    let thought: String?
    let phaseType: PhaseType
  }

  // MARK: - Language adherence drift (ADR-010 §"Out of Scope" / #401)

  /// Snapshot of the first `.languageMismatch` event in the current
  /// `run()` cycle. Once set, subsequent events do NOT overwrite —
  /// only `languageMismatchCount` increments. Cleared by
  /// ``dismissLanguageMismatchToast()`` and on `run()` entry.
  ///
  /// Why one-shot: a model that drifts once typically drifts repeatedly
  /// for the rest of the run (translation capability ceiling). Refiring
  /// the toast on every event would saturate the screen; the cumulative
  /// count is surfaced at run completion as a `LogEntry.summary` line
  /// instead (see `case .simulationCompleted` in `handleEvent`).
  nonisolated struct LanguageMismatchToast: Equatable, Sendable {
    let agent: String
    let detected: String?
    let expected: String
  }

  private(set) var pendingLanguageMismatchToast: LanguageMismatchToast?

  /// Cumulative count of `.languageMismatch` events in the current
  /// `run()` cycle. Reset on `run()` entry alongside
  /// ``pendingLanguageMismatchToast``. Surfaced at run completion as
  /// a single chat-stream `LogEntry.summary` line when > 0.
  private(set) var languageMismatchCount: Int = 0

  /// Localized toast copy derived from ``pendingLanguageMismatchToast``.
  /// Branches on `detected` nil/non-nil into two format keys so
  /// `String(format:)` never receives an `Optional<String>` (which
  /// would leak as `Optional("ja")` or `nil` in the rendered string).
  var languageMismatchToastText: String? {
    guard let pending = pendingLanguageMismatchToast else { return nil }
    let expectedName = LanguageDisplayName.resolve(pending.expected)
    if let detected = pending.detected {
      let detectedName = LanguageDisplayName.resolve(detected)
      return String(
        format: String(localized: "Output drifted to %@ (expected %@) for %@"),
        detectedName, expectedName, pending.agent)
    }
    return String(
      format: String(localized: "Output drifted from expected %@ for %@"),
      expectedName, pending.agent)
  }

  /// Clears the pending toast trigger so the host view can collapse it.
  /// Cumulative ``languageMismatchCount`` is preserved so the run-end
  /// summary line still reflects every event that fired. The toast does
  /// NOT re-fire within the same `run()` cycle, even on subsequent events.
  func dismissLanguageMismatchToast() {
    pendingLanguageMismatchToast = nil
  }

  // MARK: - Turn degradation (ADR-021 D5/D6 / #992)

  /// Cumulative count of `.turnSkipped` events in the current `run()`
  /// cycle — the App-side aggregate that mirrors ``languageMismatchCount``.
  /// Reset on `run()` entry. Persisted to the run's `SimulationRecord`
  /// (`degradedTurnCount` column) at completion and surfaced as a
  /// Results/History badge (D6). Unlike ``languageMismatchCount`` this
  /// counter is durable, so its reset semantics are load-bearing:
  /// **final-segment** — a resumed run starts from 0, so the persisted
  /// badge counts skips in the completed segment only, consistent with
  /// ADR-021 D4's breaker counter (also reset on resume). A lifetime
  /// count across resume would require persisting on pause too, which is
  /// out of PR3 scope.
  private(set) var degradedTurnCount: Int = 0

  // Running totals for weighted tok/s. See `averageTokensPerSecond`.
  private var totalCompletionTokens = 0
  private var totalInferenceSeconds: Double = 0
  // Default ON: inner thoughts provide interpretive context without drawbacks.
  var showAllThoughts = true
  var speed: PlaybackSpeed = .normal

  /// Chars-per-second to use for the committed `AgentOutputRow` of `entryId`,
  /// or `nil` when the row must not animate.
  ///
  /// Returns `nil` only for `.instant` playback
  /// (`speed.charsPerSecond == nil`) — every other speed animates. A row
  /// whose primary streamed live is NOT snapped here; it animates from its
  /// handoff seed (``handoffSeed(forEntryId:)``) and continues
  /// typing the unrevealed tail at cps (reveal-position handoff, bug 2).
  ///
  /// Uses ``PlaybackSpeed/charsPerSecond`` — the single typing-rate source of
  /// truth shared with the demo replay (``ReplayViewModel/typingCharsPerSecond``).
  ///
  /// Returns `nil` for the **latest** row once its reveal has completed
  /// (``latestRowRevealCompleted``), so a fresh `AgentOutputRow` mount on the
  /// ADR-017 Phase B adopt path snaps to full instead of re-typing. NOTE: this
  /// makes the return value intentionally NON-constant across a row's lifetime
  /// (it flips real-cps → `nil` at completion). `AgentOutputRow` tolerates that
  /// because it starts its reveal in `.onAppear` and has no `.onChange(of:
  /// charsPerSecond)` — do NOT add one, or a completed latest row would restart.
  func effectiveCharsPerSecond(forEntryId entryId: UUID) -> Double? {
    if entryId == latestAgentOutputId, latestRowRevealCompleted { return nil }
    return speed.charsPerSecond
  }

  /// Records that the latest committed row has finished its typewriter reveal,
  /// so a later View re-projection (adopt / keep-running return, ADR-017
  /// Phase B) renders it static instead of re-typing. Guarded to the current
  /// ``latestAgentOutputId`` — a stale completion from a row that is no longer
  /// latest is ignored (that row already snaps to full via `isLatest == false`).
  func markLatestRowRevealCompleted(entryId: UUID) {
    guard entryId == latestAgentOutputId else { return }
    latestRowRevealCompleted = true
  }

  /// Reveal-handoff seed for the committed row of `entryId`: the
  /// `visibleChars` position its streaming row reached at commit, or `0`
  /// for a non-streamed row (animate from the start). ``AgentOutputRow``
  /// reads this into `initialVisibleChars`.
  func handoffSeed(forEntryId entryId: UUID) -> Int {
    streamingHandoffChars[entryId] ?? 0
  }

  /// Report the in-flight streaming row's current reveal position
  /// (`visibleChars`) so a later commit can hand it off to the committed row
  /// (see ``streamingHandoffChars``). Called from the live streaming row on
  /// every reveal tick; negative values are clamped to `0`.
  func reportStreamingReveal(_ visibleChars: Int) {
    streamingRevealedChars = max(0, visibleChars)
  }

  /// Opacity of a **past** (non-current) log row when current-utterance focus
  /// is active. Dimming past rows during playback de-emphasises already-read
  /// content so the eye settles on the line being revealed — the chat-log
  /// analogue of a visual-novel "current line" stage. 0.65 keeps past rows
  /// legible (light dim, not hidden). Change-detector pinned by tests.
  static let pastFocusOpacity: Double = 0.65

  /// Pure focus-opacity decision (extracted for deterministic unit testing per
  /// `.claude/rules/view-testing.md`). Focus dimming applies **only while the
  /// run is in flight** — once it ends (or pauses for review) every row returns
  /// to full opacity so the completed log reads normally. The current row
  /// (latest committed utterance, or the in-flight streaming row) stays full.
  static func focusedOpacity(isRunning: Bool, isCurrent: Bool) -> Double {
    guard isRunning else { return 1.0 }
    return isCurrent ? 1.0 : pastFocusOpacity
  }

  /// Focus opacity for a committed log row, keyed on whether it is the latest
  /// `.agentOutput`. The in-flight streaming row is always current — `SimulationView`
  /// applies `focusedOpacity(isRunning:isCurrent: true)` to it directly.
  func opacity(forEntryId entryId: UUID) -> Double {
    Self.focusedOpacity(isRunning: isRunning, isCurrent: entryId == latestAgentOutputId)
  }

  /// Read-only view of the runner's pause state. Views observe this to drive
  /// the pause-button label and "Paused" pill. **Mutation must go through
  /// ``pauseSimulation(reason:)`` / ``resumeSimulation()``** — those methods
  /// co-manage `runner.isPaused` and `suspendController` so an in-flight
  /// generate is interrupted cooperatively rather than waiting for the next
  /// phase boundary (ADR-003 §10 invariant 6).
  ///
  /// Manual `access(keyPath:)` / `withMutation(keyPath:)` hooks bridge this
  /// computed property to the `@Observable` machinery: `SimulationRunner` is
  /// a `nonisolated` class with lock-protected internal state — NOT itself
  /// `@Observable` — so mutations of `runner.isPaused` cannot auto-trigger
  /// the macro-synthesized change tracking. Without these hooks, SwiftUI
  /// views reading `isPaused` would not re-render when the memory-warning
  /// handler flips `runner.isPaused`, leaving the play/pause button stuck.
  var isPaused: Bool {
    access(keyPath: \.isPaused)
    return runner.isPaused
  }

  // MARK: - GameHeader integration (#297 PR 3)

  /// The most recently entered phase. Drives `GameHeader`'s row-2
  /// phase-name fragment via `SimulationView`'s formatter helper.
  /// Public-read mirror of the private `currentPhaseType` so the
  /// existing persistence / log-entry callsites stay encapsulated
  /// while view-layer code still gets the typed value.
  ///
  /// Naming-aligned with `ReplayViewModel.currentPhase` so the two
  /// VMs present a parallel surface to their respective GameHeader
  /// composers (Demo's `+GameHeader.swift` extension and Sim's
  /// `headerBar` helper).
  var currentPhase: PhaseType? { currentPhaseType }

  /// Computed `GameHeaderStatus` for the always-visible status pill.
  /// Reads stored flags (`isCancelled` / `errorMessage` / `isCompleted`
  /// / `isPaused`) fresh on every observation so callers cannot snapshot
  /// a stale value across a pause→cancel flip. See
  /// ``SimulationViewModel/deriveStatus(isCancelled:errorMessage:isCompleted:isPaused:)``
  /// for the precedence and rationale.
  ///
  /// Observability of the `isPaused` axis is inherited from the manual
  /// `access(keyPath:\.isPaused)` / `withMutation(keyPath:\.isPaused)`
  /// bridge on the `isPaused` getter and mutation sites —
  /// `runner.isPaused` is non-`@Observable`, so direct flips without
  /// the bridge would leave this computed property stale. All current
  /// `runner.isPaused` mutation sites in the file are wrapped; verified
  /// by `pauseSimulationInvalidatesIsPausedObservation` in the
  /// lifecycle-test suite.
  var status: GameHeaderStatus {
    Self.deriveStatus(
      isCancelled: isCancelled,
      errorMessage: errorMessage,
      isCompleted: isCompleted,
      isPaused: isPaused
    )
  }

  /// Pure derivation of `GameHeaderStatus` from the four flags Sim's
  /// header pill cares about. Lifted to a `static` so
  /// `SimulationViewModelStatusTests` can pin every precedence pair
  /// (especially the pathological `isCancelled && errorMessage != nil`
  /// case) without having to drive the full `run()` lifecycle.
  ///
  /// **Precedence (load-bearing)**: cancellation supersedes everything
  /// because it is terminal user intent — the alternative would mean
  /// a race-condition error or a stale paused flag could mask the
  /// user's deliberate stop. Within the failure tier, an unhandled
  /// error supersedes a successful completion (a run that completed
  /// then errored during teardown is still an error from the user's
  /// perspective). `isPaused` sits below the terminal flags because a
  /// completed/cancelled/errored run with a stale paused flag (the
  /// runner clears it defensively, but precedence is defense-in-depth)
  /// must still report its terminal verdict, not "Paused".
  ///
  /// 1. `isCancelled` → `.cancelled`
  /// 2. `errorMessage != nil` → `.error`
  /// 3. `isCompleted` → `.completed`
  /// 4. `isPaused` → `.paused`
  /// 5. else → `.simulating` (running, or pre-`run()` initialization
  ///    window where the host view does not yet show the header)
  static func deriveStatus(
    isCancelled: Bool, errorMessage: String?,
    isCompleted: Bool, isPaused: Bool
  ) -> GameHeaderStatus {
    if isCancelled { return .cancelled }
    if errorMessage != nil { return .error }
    if isCompleted { return .completed }
    if isPaused { return .paused }
    return .simulating
  }

  /// Round-counter pair for `GameHeader`'s row-2 ROUND fragment.
  /// `nil` until the first `.roundStarted` event lands (`totalRounds`
  /// stays at its initial `0` until then), so the fragment doesn't
  /// flash a stale `0/0` between scenario load and first round.
  ///
  /// The pair-or-nothing invariant lives here — at the source of truth
  /// for round state — rather than at the call site. `SimulationView`
  /// passes `viewModel.headerRound` directly into `GameHeader.init`
  /// without re-deriving the guard.
  var headerRound: GameHeaderRound? {
    guard totalRounds > 0 else { return nil }
    return GameHeaderRound(current: currentRound, total: totalRounds)
  }

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
  /// Requires iOS 26+, `LlamaCppService` (for GPU↔CPU switching), and the
  /// opt-in `FeatureFlags.backgroundContinuationEnabled` flag (default
  /// `false` — see the flag's doc comment for the unstable-feature
  /// exposure-shrink rationale, the parked-indefinitely status, and the
  /// re-enable bar; gating umbrella #254).
  ///
  /// This computed property is the single source of truth for the BG
  /// continuation surface — both UI rendering (`SimulationView` toggle
  /// visibility) and VM scheduling (`enableBackgroundContinuation`'s
  /// guard) funnel through it, so flipping the flag suppresses the entire
  /// surface without needing additional UI-layer gates.
  var canEnableBackgroundContinuation: Bool {
    guard FeatureFlags.backgroundContinuationEnabled else { return false }
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
  // Viewer-prediction store (#915). Optional + nil-defaulted so fixture-driven
  // tests (which construct the VM without it) never write predictions; the gate
  // in `interceptFirstVoteIfNeeded` also requires a visible view, so tests are
  // doubly insulated. Production wires it at the `SimulationView` boundary.
  private let predictionRepository: (any PredictionRepository)?
  // Guards model-switch UI while inference is running. Optional to keep
  // the existing test fixtures (which don't need the guard) unchanged.
  private let simulationActivityRegistry: SimulationActivityRegistry?
  // Accessed from the BG continuation extension in SimulationViewModel+Background.swift
  let backgroundManager: BackgroundSimulationManager?
  // Lifecycle logger — accessed from the +Background extension. Use `info` for
  // routine state transitions and `error` for unexpected paths so device logs
  // stay readable.
  let lifecycleLogger = Logger(subsystem: "app.pastura.Pastura", category: "SimulationVM")

  // MARK: - Viewer prediction (#915)

  /// Drives `.sheet(item:)` for the prediction prompt; non-nil while the sheet
  /// is up. Set from the run loop's interception, cleared on resolution.
  private(set) var predictionPrompt: ViewerPredictionPrompt?

  /// This run's scored prediction result (hit/miss + streak), shown next to the
  /// final result card. `nil` when the run had no answered prediction. Reset
  /// per run.
  private(set) var predictionOutcome: PredictionOutcome?

  /// A pick captured at vote-phase start, awaiting the tally to be scored at
  /// `.voteResults`. Reset per run.
  private var pendingPrediction: PendingPrediction?

  /// Whether `SimulationView` is currently on screen. Gates the prediction
  /// sheet so a navigated-away (ADR-017 Phase B park) run never presents a
  /// modal (scene-background is handled separately by `isAppBackgrounded`).
  /// Defaults to `true` because the VM is only ever constructed by the
  /// on-screen `SimulationView`; the view corrects it via
  /// `setViewVisible(_:)` on appear/disappear.
  private(set) var isViewVisible = true

  /// Accumulated `.assignment` events (agent → assigned value), used to derive
  /// the wolf ground-truth at the first vote reveal. Reset per run.
  private var predictionAssignments: [String: String] = [:]

  /// Latch: set once the prediction has been offered this run (answered OR
  /// skipped), so it fires at most once with no DB round-trip. Reset per run.
  private var hasAttemptedPrediction = false

  /// Suspends the run loop while the prediction sheet awaits the viewer's
  /// answer; resumed exactly once by `resolvePrediction`.
  private var predictionContinuation: CheckedContinuation<ViewerPredictionSheet.Resolution, Never>?

  // MARK: Contradiction badge (#916)

  /// Ids of committed declaration rows (`.agentOutput` entries carrying
  /// `declared_intent`) whose declaration was contradicted by every one of
  /// that agent's choose actions in the same round. Views decorate those
  /// rows retroactively by membership lookup. VM-owned (not row `@State`)
  /// so an ADR-017 Phase B adopt re-projection neither loses nor replays
  /// the badges (`.claude/rules/swiftui-traps.md` § Re-projection). Grows
  /// monotonically over the run; reset per run.
  private(set) var contradictionBadgedEntryIDs: Set<UUID> = []

  /// Current round's `declared_intent` per agent, with the id of the
  /// committed declaration row for retroactive badging. Raw parsed values
  /// (pre-`ContentFilter`) — detection compares machine tokens, not
  /// display text. Reset each round.
  private var declaredIntents: [String: (value: String, entryID: UUID)] = [:]

  /// Current round's raw parsed choose actions per agent (both round-robin
  /// appearances). Raw, not `validateAction`-coerced — see
  /// `ContradictionDetectionLogic`. Reset each round.
  private var chooseRawActions: [String: [String]] = [:]

  #if DEBUG
    // Streaming-display diagnostic logger for #133 PR#4 device-run sessions.
    // Shared across VM + `AgentOutputRow`; filter Console.app with
    // `subsystem:app.pastura.Pastura category:StreamingDiag` to surface the 2 signals
    // feeding PR#5 ADR pivot-path decision (Hyp A retry / Hyp B recycle).
    // `.info` level so it shows without `log config` overrides on-device.
    static let streamingDiagLogger = Logger(
      subsystem: "app.pastura.Pastura", category: "StreamingDiag")

    // Per-agent in-flight attempt counter for Hyp A (parse-retry silent
    // transition). `LLMCaller.call` emits `.inferenceStarted` +
    // `.inferenceCompleted` *per attempt* inside its retry loop — so clearing
    // on `.inferenceCompleted` would collapse the retry signal. We instead
    // clear on `.agentOutput` (per-turn commit) and on `run()` entry.
    //
    // Load-bearing assumption: ADR-002 §6 — the Engine runs inferences
    // sequentially, so a single `[String: Int]` keyed on agent name cannot
    // conflate interleaved agents. If Phase 3 ever parallelises `speak_all`,
    // this dict becomes racy and must be reworked.
    private var inflightInferenceAttempts: [String: Int] = [:]

    // Previous-raw-primary tracker for Hyp A' (silent stream re-issue).
    // `LLMCaller.consumeStreamWithSuspendRetry` re-issues the stream on
    // `.suspended` without firing `.inferenceStarted` — visually identical
    // to a parse retry (streaming row's text restarts) but invisible to
    // the attempt counter above. We catch it by remembering the last raw
    // `primary` per agent and logging when the next one is neither an
    // extension nor a shrink-to-prefix (i.e. content diverged).
    //
    // Uses raw (pre-ContentFilter) primary so filter rewrites like
    // "fuck" → "***" aren't mistaken for a reset.
    private var lastRawStreamingPrimary: [String: String] = [:]
  #endif
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

  /// True while the LLM model is being loaded from disk at the start of a
  /// run / resume (before the first `SimulationEvent`). Surfaced to the UI so
  /// it can show a "Loading model..." overlay over the still-empty log — the
  /// load reads a multi-GB GGUF + inits the Metal context and takes a few
  /// seconds (HIG: show progress for waits of unquantifiable duration). The
  /// initial-load sibling of ``isReloadingModel`` (GPU↔CPU switch). (#822)
  /// `private(set)`: only mutated here in `run()` / `resume()` (same file).
  private(set) var isLoadingModel = false

  // MARK: Opening-card intro gate (#853)
  //
  // Coordinates the opening-card premise reveal with the run lifecycle so the
  // premise types on a clean background WHILE the model loads, and the
  // conversation only starts AFTER the reveal finishes. Three collaborators:
  // the View arms the gate (``beginIntro()``) iff there is a premise card, the
  // card signals completion (``introRevealDidComplete()``), and `run()` waits
  // at ``awaitIntroReveal()`` between model load and engine start. All state is
  // MainActor-isolated (the VM is `@MainActor`), so the latch + continuation
  // handoff needs no lock and cannot double-resume across actors.

  /// Set by the View at run start when an opening card will be shown, so `run()`
  /// knows to wait for the reveal. Unarmed runs (no premise, or resume) skip the
  /// wait entirely.
  private var introGateArmed = false
  /// Latch: the reveal has finished (or was released). Read by
  /// ``awaitIntroReveal()`` so a completion that fires *before* the gate is
  /// awaited (the common fast-reveal / slow-load case) is not missed.
  private var introRevealCompleted = false

  /// Latch: the opening-card premise reveal has BEGUN (or already run) for this
  /// run. Read by `SimulationView`'s premise-card `charsPerSecond` guard so the
  /// card renders static on the ADR-017 Phase B adopt path: when a parked run is
  /// re-projected into a fresh `SimulationView`, that view's per-`@State` reveal
  /// latch would reset and re-type the premise. Living on the surviving VM,
  /// this latch survives re-projection. Set on the animated reveal's start
  /// (`onRevealStarted` → ``markIntroRevealBegan()``); reset per `beginIntro`.
  private(set) var introRevealHasBegun = false
  /// The suspended `run()` continuation, when the gate is awaited before the
  /// reveal completes. Stored-then-nilled on first resume so a second resume
  /// (timeout backstop / cancellation / late signal) can never trap.
  private var introContinuation: CheckedContinuation<Void, Never>?
  /// Last-resort backstop so a card that never signals can't freeze the run
  /// forever. Cancelled on normal completion; should never fire in practice.
  private var introTimeoutTask: Task<Void, Never>?

  /// True while the opening-card premise is still revealing — armed but not yet
  /// complete. Drives ``SimulationDisplayState`` to suppress the model-load
  /// scrim so the premise types on a clean background (the load runs behind it).
  var isPlayingIntro: Bool { introGateArmed && !introRevealCompleted }

  /// Arms the intro gate at run start (View-driven, only when an opening card
  /// will be shown — the View owns the single premise-visibility predicate, so
  /// the gate can't wait for a card that never renders). Starts the backstop.
  ///
  /// `revealBackstop` is a last-resort cap (should never fire): the caller sizes
  /// it above the real reveal time (premise length ÷ slowest playback speed +
  /// buffer) so a card that silently never signals can't freeze the run, without
  /// clipping a long premise typing at the slow speed.
  func beginIntro(revealBackstop: TimeInterval) {
    introGateArmed = true
    introRevealCompleted = false
    introRevealHasBegun = false
    introTimeoutTask?.cancel()
    introTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(revealBackstop))
      self?.introRevealDidComplete()
    }
  }

  /// Signalled by the opening card when its reveal finishes (both the typed and
  /// static paths). Idempotent: latches, clears ``isPlayingIntro``, cancels the
  /// backstop, and resumes any waiting `run()`. Safe to call unarmed / twice.
  func introRevealDidComplete() {
    guard !introRevealCompleted else { return }
    introRevealCompleted = true
    introTimeoutTask?.cancel()
    introTimeoutTask = nil
    resumeIntroContinuation()
  }

  /// Signalled by the opening card when its typewriter reveal *starts* (only the
  /// animated path fires it, per `ScenarioIntroCard.onRevealStarted`). Latches
  /// ``introRevealHasBegun`` so a later View re-projection (ADR-017 Phase B
  /// adopt) renders the premise static instead of re-typing.
  func markIntroRevealBegan() {
    introRevealHasBegun = true
  }

  /// Resumes the stored `run()` continuation exactly once (store-then-nil).
  private func resumeIntroContinuation() {
    if let continuation = introContinuation {
      introContinuation = nil
      continuation.resume()
    }
  }

  /// Awaited by `run()` between model load and engine start. Returns immediately
  /// when the gate is unarmed or the reveal already completed; otherwise suspends
  /// until ``introRevealDidComplete()`` fires. Cancellation-aware: a run torn
  /// down mid-reveal (navigate-away) resumes promptly rather than stalling.
  func awaitIntroReveal() async {
    guard introGateArmed, !introRevealCompleted else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // Re-check under MainActor: completion may have latched between the
        // guard above and here (no real suspension in between, but cheap
        // insurance) — resume at once rather than storing a stale continuation.
        if introRevealCompleted {
          continuation.resume()
        } else {
          introContinuation = continuation
        }
      }
    } onCancel: {
      // The cancel handler runs outside actor isolation; hop back to release.
      Task { @MainActor [weak self] in self?.resumeIntroContinuation() }
    }
  }

  /// Set by the host `SimulationView` while the persona-detail sheet is up
  /// (#942 PR2). One signal drives both playback layers: the consume loops in
  /// ``run(scenario:llm:scenarioCategorySnapshot:)`` / ``resume(record:scenario:llm:)``
  /// (Layer B) poll it via ``awaitPlaybackUnheld()``, and `AgentOutputRow`'s
  /// reveal loop (Layer C) reads it live through its `isTypingParked` closure —
  /// so both the event stream and the visible typewriter freeze coherently.
  ///
  /// `@ObservationIgnored`: Tasks/closures read it per-tick and no view renders
  /// from it, so `@Observable` tracking would be pure churn. Engine keeps
  /// running while held (ADR-017-untouched Option A) — the unbounded
  /// `AsyncStream` buffers ahead, the same bounded trade-off as the
  /// viewer-prediction wait. Defensively reset at each run/resume start so a
  /// stale `true` (a sheet dismissed across an ADR-017 re-projection, or a
  /// dropped `onDismiss`) can never start a fresh run frozen.
  @ObservationIgnored var isPlaybackHeldForSheet = false

  /// Suspend the consume loop while ``isPlaybackHeldForSheet`` holds playback.
  /// Poll form (not a continuation) mirrors `AgentOutputRow`'s reveal park and
  /// keeps the producer buffering under Option A; the enclosing `for await`
  /// still tears down promptly on cancellation. #942 PR2.
  private func awaitPlaybackUnheld() async {
    while isPlaybackHeldForSheet && !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  /// Holds the currently running simulation task for cancellation support.
  /// Set by the caller (SimulationView) after launching `run()` in a Task.
  /// Memory warning or explicit user action can cancel via `cancelSimulation()`.
  var runTask: Task<Void, Never>?

  /// Cooperative suspend/resume channel for the active inference. Created per
  /// `run()` call and attached to the LLM so scene-phase / BG-task handlers
  /// (in the +Background extension) can interrupt an in-flight `generate`.
  /// Cleared on `run()` exit.
  var suspendController: SuspendController?

  /// The app-level session that owns this run, set by
  /// ``SimulationSession/startGuarded(source:scenario:tab:makeViewModel:body:)``.
  ///
  /// Phase B (ADR-017): the non-terminal suspend/resume triggers (user-pause,
  /// scene-phase background) route through the session's park gate so they
  /// compose with the view-hide park on one reason set instead of touching the
  /// ``SuspendController`` directly and desyncing. Weak — the session owns the
  /// view model, not the reverse. `nil` in fixture tests that build the VM
  /// directly, where ``routePark(reason:)`` falls back to the controller.
  @ObservationIgnored weak var session: SimulationSession?

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

  /// Phase-path stack mirror of `currentPhaseType`, tracked via both
  /// `.phaseStarted` (push) and `.phaseCompleted` (pop). Used to persist the
  /// `phasePathJSON` column on `TurnRecord` / `CodePhaseEventRecord` so that
  /// scenarios with a top-level `speak_all` AND a nested `speak_all` inside a
  /// conditional branch keep distinct lineage in exports (#143).
  ///
  /// Why pop on `.phaseCompleted` (unlike `currentPhaseType`): an event
  /// emitted in the gap between an inner sub-phase's completion and the next
  /// `.phaseStarted` would otherwise be mis-attributed to the stale sub-phase
  /// path. Pop only when the completed path matches the current one AND
  /// `count > 1` — so completing a top-level phase leaves the stack empty
  /// (matches the "no active phase" starting state) and a mismatched
  /// `.phaseCompleted` (impossible under `SimulationRunner`'s contract, but
  /// defensive) is a no-op.
  private var currentPhasePath: [Int]?

  init(
    runner: SimulationRunner = SimulationRunner(),
    contentFilter: ContentFilter = ContentFilter(),
    simulationRepository: any SimulationRepository,
    turnRepository: any TurnRepository,
    codePhaseEventRepository: (any CodePhaseEventRepository)? = nil,
    scenarioRepository: (any ScenarioRepository)? = nil,
    predictionRepository: (any PredictionRepository)? = nil,
    backgroundManager: BackgroundSimulationManager? = nil,
    simulationActivityRegistry: SimulationActivityRegistry? = nil
  ) {
    self.runner = runner
    self.contentFilter = contentFilter
    self.simulationRepository = simulationRepository
    self.turnRepository = turnRepository
    self.codePhaseEventRepository = codePhaseEventRepository
    self.scenarioRepository = scenarioRepository
    self.predictionRepository = predictionRepository
    self.backgroundManager = backgroundManager
    self.simulationActivityRegistry = simulationActivityRegistry
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
    withMutation(keyPath: \.isPaused) {
      runner.isPaused = true
    }
    routePark(reason: .userPause)
    // Persist `.paused` so the run survives navigating away and surfaces on
    // the Home "paused" card. The full state snapshot is already persisted by
    // the round-boundary checkpoint consumer; this only flips the status
    // column. `didPersistPaused` guards the `run()` terminal ladder.
    didPersistPaused = true
    enqueueStatusWrite(.paused)
  }

  /// Resumes a paused simulation. Symmetric counterpart to
  /// ``pauseSimulation(reason:)`` — wakes any parked generate and unblocks
  /// the runner's phase-boundary checkpoint.
  func resumeSimulation() {
    lifecycleLogger.info("resumeSimulation: isPaused=\(self.isPaused)")
    withMutation(keyPath: \.isPaused) {
      runner.isPaused = false
    }
    routeUnpark(reason: .userPause)
    // Restore `.running` and clear the survival flag so a subsequent normal
    // completion writes `.completed` rather than leaving a stale `.paused`.
    if didPersistPaused {
      didPersistPaused = false
      enqueueStatusWrite(.running)
    }
  }

  /// Routes a **non-terminal** suspend through the session's park gate so the
  /// user-pause / scene-phase-background triggers compose with the view-hide
  /// park on one reason set (Phase B, ADR-017). Falls back to the
  /// ``SuspendController`` directly when no session owns this run (fixture tests
  /// build the VM without a session), preserving pre-Phase-B behaviour.
  ///
  /// The **terminal** suspend/resume paths (`cancelSimulation`, the `run()` /
  /// `resume()` cleanup `defer`s) deliberately bypass this and touch the
  /// controller directly — they fire only as a run ends, where an over-resume is
  /// harmless and the gate would add nothing.
  func routePark(reason: SimulationSession.ParkReason) {
    if let session {
      session.requestPark(reason: reason)
    } else {
      suspendController?.requestSuspend()
    }
  }

  /// Routes a **non-terminal** resume through the session's park gate — resumes
  /// only when no other park reason still holds. See ``routePark(reason:)``.
  func routeUnpark(reason: SimulationSession.ParkReason) {
    if let session {
      session.requestResume(reason: reason)
    } else {
      suspendController?.resume()
    }
  }

  func cancelSimulation(caller: String = #function) {
    lifecycleLogger.info(
      "cancelSimulation called by \(caller, privacy: .public): isRunning=\(self.isRunning), isOnCPU=\(self.isOnCPU), isReloadingModel=\(self.isReloadingModel)"
    )
    runTask?.cancel()
    // Defensive: if the run loop is suspended awaiting the prediction sheet
    // (a `Never` continuation that ignores task cancellation), resolve it so
    // the loop can unwind rather than leaking the continuation (#915). Normally
    // unreachable — the modal covers the stop button — but cheap insurance.
    resolvePrediction(.skipped)
    isCancelled = true
    // User-initiated cancel supersedes a prior pause: clear the survival flag
    // so the terminal ladder writes `.cancelled` (its `isCancelled` branch
    // already precedes `didPersistPaused`, but keep the state coherent).
    didPersistPaused = false
    // Cancellation supersedes pause. Two consumers depend on `isPaused`
    // being cleared here:
    //  1. `GameHeader`'s status pill (#297 PR 3) — defense-in-depth.
    //     The new `status` derivation explicitly checks `isCancelled`
    //     first (see `deriveStatus(...)`), so the pill would report
    //     `.cancelled` even without this clear. Keeping it ensures any
    //     future precedence reorder cannot reintroduce the "orange
    //     Paused pill on a cancelled run" regression.
    //  2. The pause-button icon flip (`pause.fill` ↔ `play.fill`) —
    //     load-bearing. The button reads `isPaused` directly; without
    //     this clear, a cancelled run would render the play icon as
    //     if waiting for the user to resume. The status pill's
    //     precedence does not cover this widget.
    withMutation(keyPath: \.isPaused) {
      runner.isPaused = false
    }
    // Release a generate currently parked in `awaitResume()` so cancellation
    // propagates promptly from a suspended state. Idempotent per contract.
    suspendController?.resume()
    // Events emitted after cancellation are dropped by the terminated AsyncStream,
    // so clear UI "in-progress" state here to avoid stuck "thinking..." indicators.
    thinkingAgents.removeAll()
  }

  /// Resets per-run state shared by a fresh ``run(scenario:llm:)`` and a
  /// resumed ``resume(record:scenario:llm:)``, bridges the `isPaused`
  /// observation, creates + attaches a fresh ``SuspendController``, and starts
  /// both persistence consumers. Returns the controller so the caller can wire
  /// it into the runner and its cleanup `defer`.
  ///
  /// **Zero mode flags by design.** State that DIVERGES between fresh and
  /// resumed runs is deliberately NOT touched here and stays in each caller:
  /// `scores` / `eliminated` / `totalRounds` (fresh zeroes from the scenario
  /// vs resume rehydrates from the persisted `SimulationState`), `simulationId`
  /// + `createSimulationRecord` (a new UUID vs the existing run's id), and
  /// `turnSequence` (reset to `0` vs reseeded from the persisted MAX). The
  /// `simulationActivityRegistry.enter()` / `defer { … leave() }` / `for await`
  /// consumption loop also stay in each caller as a matched-pair anchor
  /// (ADR-003 §10) — splitting them across the helper boundary would risk an
  /// unmatched `enter()` on an early cancellation.
  private func prepareRunInfrastructure(llm: any LLMService) async -> SuspendController {
    currentLLM = llm
    isRunning = true
    isCompleted = false
    isCancelled = false
    didPersistPaused = false
    isResumedRun = false
    statusWriteTask = nil
    errorMessage = nil
    logEntries = []
    // Result accumulators for the final-ranking card (#868) — reset per run so
    // a re-used VM instance does not inherit the previous simulation's tallies.
    // The resume path re-seeds these below from the checkpoint / replayed log.
    voteResults = [:]
    eliminationVotes = [:]
    // Viewer-prediction accumulators (#915) — reset so a re-used VM does not
    // inherit the previous run's assignments or the once-per-run latch.
    predictionAssignments = [:]
    hasAttemptedPrediction = false
    // Contradiction-badge accumulators (#916) — reset so a re-used VM does
    // not badge rows of a previous run (the ids would be stale anyway).
    contradictionBadgedEntryIDs = []
    declaredIntents = [:]
    chooseRawActions = [:]
    predictionPrompt = nil
    predictionOutcome = nil
    pendingPrediction = nil
    // Latent: a second run on the same VM instance would otherwise inherit
    // these from the previous simulation — `latestAgentOutputId` points at a
    // UUID no longer in `logEntries`, and `streamingSnapshot` could render a
    // stale in-flight row under a brand-new scenario.
    latestAgentOutputId = nil
    latestRowRevealCompleted = false
    streamingSnapshot = nil
    streamingHandoffChars = [:]
    streamingRevealedChars = 0
    lastAgentOutputReveal = nil
    // ADR-010 §"Out of Scope" — language-mismatch surface state must reset
    // per run so a re-used VM does not inherit the previous run's toast
    // pending or accumulated count.
    pendingLanguageMismatchToast = nil
    languageMismatchCount = 0
    // ADR-021 D6 — reset per run so a re-used (or resumed) VM does not
    // inherit the previous segment's skip count. Final-segment semantics:
    // see the ``degradedTurnCount`` doc-comment.
    degradedTurnCount = 0
    // Defense against VM reuse: today production creates a fresh VM per view
    // load, but that is not a documented invariant. A VM reused after a
    // pause-then-cancel sequence would otherwise start the next run with
    // `runner.isPaused == true` and show the resume icon on Round 1.
    withMutation(keyPath: \.isPaused) {
      runner.isPaused = false
    }
    #if DEBUG
      inflightInferenceAttempts = [:]
      lastRawStreamingPrimary = [:]
    #endif
    currentPhaseType = nil
    currentPhasePath = nil

    // Attach BEFORE loadModel so scene-phase handlers can signal suspend as
    // soon as the run is in flight.
    let controller = SuspendController()
    suspendController = controller
    await llm.attachSuspendController(controller)

    // Start both persistence consumers before any events can arrive.
    startPersistenceConsumer()
    startCodePhasePersistenceConsumer()
    return controller
  }

  /// Starts the simulation, consuming events and persisting results.
  ///
  /// `scenarioCategorySnapshot` is the source scenario's gallery category
  /// (`GalleryCategory` raw value), passed by the launch callsite that already
  /// holds the `ScenarioRecord` (#748). Unlike name / YAML — derivable from the
  /// live `scenario` domain object — category is gallery metadata absent from
  /// the YAML, so it is threaded in here rather than reached for from the
  /// repository (which would reintroduce the refetch-by-id drift the snapshot
  /// design deliberately avoids). `nil` for local / self-made scenarios.
  func run(  // swiftlint:disable:this function_body_length
    scenario: Scenario, llm: any LLMService, scenarioCategorySnapshot: String? = nil
  ) async {
    // Defensive: a fresh run must never start frozen. The persona sheet's
    // dismiss normally clears this, but a hold left stale across an ADR-017
    // re-projection (or a dropped `onDismiss`) would otherwise stall Layer B
    // before the first event. #942 PR2.
    isPlaybackHeldForSheet = false
    let controller = await prepareRunInfrastructure(llm: llm)
    scores = Dictionary(uniqueKeysWithValues: scenario.personas.map { ($0.name, 0) })
    eliminated = Dictionary(uniqueKeysWithValues: scenario.personas.map { ($0.name, false) })
    totalRounds = scenario.rounds

    // Create simulation record
    let simId = UUID().uuidString
    simulationId = simId
    let initialState = SimulationState.initial(for: scenario)
    await createSimulationRecord(
      simId: simId, scenario: scenario, state: initialState, llm: llm,
      scenarioCategorySnapshot: scenarioCategorySnapshot)

    turnSequence = 0
    lifecycleLogger.info("run() entered: simId=\(simId)")
    // Bracket inference activity with the registry. Placed immediately
    // before the cleanup defer so no awaitable step runs between them —
    // any cancellation before this point happens before enter(), so
    // leave() stays matched.
    simulationActivityRegistry?.enter()
    // Guarantee cleanup in ALL exit paths (LLM load failure, cancellation, etc.).
    // KEEP IN SYNC with resume()'s defer (hand-duplicated matched-pair anchor).
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
      // Safety net for the early-return / cancellation paths; the success path
      // clears it explicitly below before the event stream so the overlay is
      // gone while the log fills.
      isLoadingModel = false
      currentLLM = nil
      suspendController = nil
      // Intro-gate teardown (#853): cancel the reveal backstop so it can't
      // outlive the run, and disarm so `isPlayingIntro` settles to false on
      // EVERY exit (normal / load-failure early-return / cancel — the last two
      // never reach the reveal-complete latch, so without this the flag would
      // linger until dealloc). The gate's own cancellation handler already
      // resumed any waiting `awaitIntroReveal()` on task-cancel (this defer runs
      // only once `run()` returns, so it can't rescue a still-suspended gate —
      // the cancellation handler / latch does that). No-op in resume() (unarmed).
      introTimeoutTask?.cancel()
      introTimeoutTask = nil
      introGateArmed = false
      simulationActivityRegistry?.leave()
    }

    // Load LLM model
    isLoadingModel = true
    do {
      try await llm.loadModel()
    } catch {
      // #427 — show the inner `LocalizedError` text directly. The previous
      // "Failed to load LLM: \(...)" form also triggered the LocalizedStringKey
      // catalog-miss trap (interpolation runs before lookup), so dropping the
      // prefix simultaneously fixes the stack-and-leak class of bug.
      errorMessage = error.localizedDescription
      await persistStatus(.failed)
      return
    }
    isLoadingModel = false

    // Opening-card intro gate (#853): the model has loaded (concurrently with
    // the premise reveal, whose scrim was suppressed via `isPlayingIntro`); now
    // wait for the reveal to finish before the conversation begins. LOAD-BEARING
    // ORDERING: this MUST sit after `isLoadingModel = false` and BEFORE
    // `runner.run(...)` is created below — the runner's producer Task starts at
    // stream creation, so awaiting here (not after) keeps inference from running
    // and buffering ahead during the reveal. No-op for unarmed runs.
    await awaitIntroReveal()

    // Consume event stream. Agent outputs are paced by the per-row typing
    // animation in AgentOutputRow; other events (phase/round separators,
    // code-phase results) get a small fixed delay so they stay on-screen
    // long enough to read. `.instant` skips both.
    let readingScript = ReadingScript.resolve(engineLanguage: scenario.engineLanguage)
    for await event in runner.run(
      scenario: scenario, llm: llm, suspendController: controller
    ) {
      // Playback park (#942 PR2): stop consuming while the persona sheet is up
      // so the on-screen log freezes coherently with AgentOutputRow's own
      // reveal park. The producer keeps running (Option A); the AsyncStream
      // buffers ahead — the same bounded trade-off as the viewer-prediction
      // wait below — so nothing deadlocks.
      await awaitPlaybackUnheld()

      if case .agentOutput = event {
        // Reveal is paced by AgentOutputRow's typing animation, not an
        // inter-event sleep; the reading pause is applied AFTER dispatch
        // (below) so a fully-revealed line gets a beat before the next event.
      } else if speed.interEventDelayMs > 0 {
        try? await Task.sleep(for: .milliseconds(speed.interEventDelayMs))
      }

      // Viewer prediction (#915): present the sheet at the first vote-phase
      // START (before any vote is shown, so the outcome isn't spoiled) and score
      // the captured pick when the tally arrives. `run()` only (a resumed run
      // never asks). The unbounded AsyncStream buffers ahead during the wait
      // (accepted trade-off), so the producer never deadlocks.
      await handleViewerPredictionEvent(event: event, scenario: scenario)

      handleEvent(event, scenario: scenario)

      // VN-style reading pause after a committed utterance (Sim-only).
      if case .agentOutput = event {
        await holdAfterAgentOutput(script: readingScript)
      }
    }

    await finalizeRun(llm: llm)
  }

  /// Drains both persistence queues, unloads the model, settles any in-flight
  /// status write, then persists the terminal status. Shared by
  /// ``run(scenario:llm:)`` and ``resume(record:scenario:llm:)`` — the drain
  /// must complete before the status write because `fetchExportPayload` guards
  /// on `.completed`, so unflushed turn writes would race a post-run export.
  ///
  /// **Terminal ladder precedence (load-bearing).** `didPersistPaused` is
  /// checked FIRST and wins over `errorMessage`: a run torn down while still
  /// explicitly paused (navigate-away) keeps its resumable `.paused` row, and
  /// any `errorMessage` in that window is the teardown's own cancellation
  /// artifact, NOT a genuine failure (a paused run is parked — no inference can
  /// fail — and a real error would have ended the run before a pause was even
  /// possible). User-cancel clears `didPersistPaused`, so it never collides.
  /// For non-paused exits a real error beats a normal end, and explicit
  /// user-cancel beats a normal end.
  ///
  /// The `!isCompleted` branch keeps **any** run torn down mid-flight (tab-switch
  /// / back / swipe-back, with no explicit pause, cancel, or error) at `.paused`
  /// so it stays resumable from its latest round-boundary checkpoint — fresh and
  /// resumed runs alike. `isCompleted` is set only by the `.simulationCompleted`
  /// event, so a run that genuinely exhausted its stream still falls through to
  /// `.completed`; only a teardown that ends the event loop early lands here with
  /// `isCompleted == false`. Home P3 PR2 (#673) lifted the prior fresh-vs-resumed
  /// asymmetry that silently mislabelled a torn-down fresh run as `.completed`
  /// (data loss) — the in-app confirm-on-leave dialog pauses explicitly, but this
  /// branch is the lossless safety net for the un-prompted swipe-back path.
  private func finalizeRun(llm: any LLMService) async {
    // finish() is idempotent; defer also calls it for early-return paths.
    persistenceContinuation?.finish()
    codePhasePersistenceContinuation?.finish()
    await persistenceTask?.value
    await codePhasePersistenceTask?.value
    try? await llm.unloadModel()
    // Drain any in-flight `.paused` / `.running` status write so the terminal
    // decision below observes (and writes after) the settled status column.
    await statusWriteTask?.value

    if let status = Self.terminalStatus(
      didPersistPaused: didPersistPaused, errorMessage: errorMessage,
      isCancelled: isCancelled, isCompleted: isCompleted) {
      await persistStatus(status)
      // ADR-021 D6 — record the aggregate skip count only for a run that
      // reached the end. The column already holds 0 from run-creation, so a
      // no-skip run needs no write; a breaker/error abort stays at 0 (D6:
      // a `.failed` run persists exactly as today).
      if status == .completed, degradedTurnCount > 0 {
        await persistDegradedTurnCount(degradedTurnCount)
      }
    } else {
      lifecycleLogger.info("run exited while paused; leaving .paused for resume")
    }
  }

  /// Pure terminal-status decision for ``finalizeRun(llm:)``. Returns the status
  /// to persist, or `nil` to leave the existing row untouched (the explicit
  /// `.paused` resume point). Lifted to a `static` so the precedence — including
  /// the mid-flight-teardown branch — is unit-testable without driving a full run
  /// (mirrors ``deriveStatus(isCancelled:errorMessage:isCompleted:isPaused:)``).
  ///
  /// Precedence (load-bearing): see ``finalizeRun(llm:)``'s doc-comment for the
  /// `didPersistPaused`-first rationale and the `!isCompleted` mid-flight-teardown
  /// branch. `isResumedRun` is deliberately NOT a parameter — the teardown branch
  /// is symmetric across fresh and resumed runs (#673); the field still gates the
  /// `.error(.cancelled)` suppression in `handleEvent`, which is a separate concern.
  static func terminalStatus(
    didPersistPaused: Bool, errorMessage: String?,
    isCancelled: Bool, isCompleted: Bool
  ) -> SimulationStatus? {
    if didPersistPaused { return nil }
    if errorMessage != nil { return .failed }
    if isCancelled { return .cancelled }
    if !isCompleted { return .paused }
    return .completed
  }

  /// Resumes a previously-paused simulation from its persisted checkpoint.
  ///
  /// Symmetric counterpart to ``run(scenario:llm:)`` for a run whose `.paused`
  /// row already exists. The caller (``SimulationView``'s resume entry) hands in
  /// the persisted `record` and the snapshot-resolved `scenario` so a live
  /// scenario edit / deletion cannot drift the resumed run.
  ///
  /// **Four resume hazards, each handled inline below:**
  /// 1. **Model not loaded** — `loadModel()` runs first; a failure leaves the
  ///    DB row `.paused` (never `.failed`) so the run stays resumable, and
  ///    surfaces the run in-memory as paused (not errored).
  /// 2. **Scenario drift** — the run executes against the passed `scenario`
  ///    (snapshot-resolved upstream via ``ScenarioSnapshotResolver``), never a
  ///    re-fetched live row that may have been edited or deleted.
  /// 3. **Sequence-number collision** — round-`> K` partial-round rows are
  ///    deleted, then `turnSequence` is reseeded from the surviving MAX
  ///    (last-used value) so the pre-increment in `persistTurnRecord` /
  ///    `persistCodePhaseEvent` continues the sequence without gap or collision.
  /// 4. **BG re-attach is VM-local** — a fresh ``SuspendController`` is created
  ///    per resume (via `prepareRunInfrastructure`), never shared across runs
  ///    (ADR-003 §10 invariant 1).
  ///
  /// - Parameters:
  ///   - record: The persisted `.paused` run to resume. `record.stateJSON`
  ///     decodes to the checkpoint; `record.id` is reused (no new UUID).
  ///   - scenario: The snapshot-resolved scenario the run executes against.
  ///   - llm: The LLM service for inference.
  func resume(  // swiftlint:disable:this function_body_length
    record: SimulationRecord, scenario: Scenario, llm: any LLMService
  ) async {
    guard let state = decodeState(from: record) else {
      // Unreadable checkpoint — nothing is set up yet, so a bare return leaves
      // the DB row untouched (still `.paused`).
      lifecycleLogger.error(
        "resume: failed to decode state for simId=\(record.id, privacy: .public)")
      return
    }
    // `currentRound` on the checkpoint is the just-COMPLETED round K (the
    // producer emits `.roundCheckpoint` only after `.roundCompleted`); resume
    // re-enters at K+1.
    let completedRound = state.currentRound
    let startRound = completedRound + 1
    let simId = record.id
    let turnRepo = turnRepository
    let codeRepo = codePhaseEventRepository

    // Prune the partial round-`> K` rows and compute the reseed BEFORE touching
    // any run state, so a DB failure aborts cleanly with the row still `.paused`
    // and no half-started run. Reseed = the surviving MAX (last-used value): the
    // pre-increment at persist time then yields MAX+1 for the first resumed row
    // — contiguous, no gap, no collision. Empty tables (e.g. a pause before any
    // round completed, K=0) yield `?? 0`, so the first resumed row gets seq 1.
    let reseedValue: Int
    let history: ([TurnRecord], [CodePhaseEventRecord])
    do {
      reseedValue = try await offMain {
        try turnRepo.deleteBySimulationId(simId, roundNumberGreaterThan: completedRound)
        try codeRepo?.deleteBySimulationId(simId, roundNumberGreaterThan: completedRound)
        let turnMax = try turnRepo.maxSequenceNumber(simulationId: simId)
        let codeMax = (try codeRepo?.maxSequenceNumber(simulationId: simId))
        return [turnMax, codeMax].compactMap { $0 }.max() ?? 0
      }
      history = try await offMain {
        let turns = try turnRepo.fetchBySimulationId(simId)
        let events = (try codeRepo?.fetchBySimulationId(simId)) ?? []
        return (turns, events)
      }
    } catch {
      lifecycleLogger.error(
        "resume: DB prune/fetch failed, leaving .paused: \(String(describing: error), privacy: .public)"
      )
      return
    }

    // Defensive: mirror run()'s stale-hold clear so a resumed run never starts
    // frozen (#942 PR2).
    isPlaybackHeldForSheet = false
    let controller = await prepareRunInfrastructure(llm: llm)
    simulationId = simId
    isResumedRun = true
    totalRounds = scenario.rounds
    // Rehydrate accumulated state from the checkpoint (NOT from the replayed
    // log entries — those are display-only; see ResumeLogReplayMapper).
    scores = state.scores
    eliminated = state.eliminated
    // Re-seed the final-ranking card's vote-only tallies from the checkpoint
    // (#868); `SimulationState` persists `voteResults` but not the per-agent
    // elimination counts, so those are rebuilt from the replayed log below.
    voteResults = state.voteResults
    currentRound = completedRound
    turnSequence = reseedValue
    let items = ResultDetailTimelineBuilder.build(turns: history.0, events: history.1)
    logEntries = ResumeLogReplayMapper.map(
      items: items, totalRounds: scenario.rounds, contentFilter: contentFilter)
    // Rebuild per-agent elimination counts from the replayed log so a run
    // resumed after an earlier-round elimination still shows that agent's own
    // vote count in the survival framing (#868). Not persisted in state, and
    // the replay does not route through `handleElimination`.
    for entry in logEntries {
      if case .elimination(let agent, let voteCount) = entry.kind {
        eliminationVotes[agent] = voteCount
      }
    }

    lifecycleLogger.info(
      "resume() entered: simId=\(simId, privacy: .public), startRound=\(startRound)")
    simulationActivityRegistry?.enter()
    // Hand-duplicated from run()'s cleanup defer (matched-pair anchor — see
    // prepareRunInfrastructure's doc). KEEP IN SYNC with run()'s defer: any
    // change to one (teardown order, completeTask, registry leave) must mirror.
    defer {
      lifecycleLogger.info(
        "resume() defer: isCompleted=\(self.isCompleted), isCancelled=\(self.isCancelled), errorMessage=\(self.errorMessage ?? "nil")"
      )
      controller.resume()
      persistenceContinuation?.finish()
      codePhasePersistenceContinuation?.finish()
      backgroundManager?.completeTask(success: isCompleted)
      isRunning = false
      // Mirror run()'s defer (matched-pair anchor): clear the load overlay on
      // the early-return / cancellation paths.
      isLoadingModel = false
      currentLLM = nil
      suspendController = nil
      // Intro-gate teardown (#853): cancel the reveal backstop so it can't
      // outlive the run, and disarm so `isPlayingIntro` settles to false on
      // EVERY exit (normal / load-failure early-return / cancel — the last two
      // never reach the reveal-complete latch, so without this the flag would
      // linger until dealloc). The gate's own cancellation handler already
      // resumed any waiting `awaitIntroReveal()` on task-cancel (this defer runs
      // only once `run()` returns, so it can't rescue a still-suspended gate —
      // the cancellation handler / latch does that). No-op in resume() (unarmed).
      introTimeoutTask?.cancel()
      introTimeoutTask = nil
      introGateArmed = false
      simulationActivityRegistry?.leave()
    }

    // Hazard 1: load the model first. A failure must NOT reuse run()'s
    // `.failed` path (that would destroy the resume point) — leave the DB row
    // `.paused` (no status write below, since we return before `.running` is
    // enqueued) and present the run as paused in-memory so the user can retry
    // from the Home card.
    isLoadingModel = true
    do {
      try await llm.loadModel()
    } catch {
      lifecycleLogger.error(
        "resume: loadModel failed, leaving run resumable: \(String(describing: error), privacy: .public)"
      )
      withMutation(keyPath: \.isPaused) {
        runner.isPaused = true
      }
      return
    }
    isLoadingModel = false
    // Model is up — flip the DB row `.paused` → `.running`. Gated on loadModel
    // success: writing `.running` before the load would strand the row as
    // `.running` on a load failure with no easy restore to `.paused`.
    enqueueStatusWrite(.running)

    let readingScript = ReadingScript.resolve(engineLanguage: scenario.engineLanguage)
    for await event in runner.run(
      scenario: scenario, llm: llm, suspendController: controller,
      resumingFrom: state, startRound: startRound
    ) {
      // Playback park (#942 PR2): mirror run()'s consume-loop gate.
      await awaitPlaybackUnheld()

      if case .agentOutput = event {
        // Reveal is paced by AgentOutputRow's typing animation, not an
        // inter-event sleep; the reading pause is applied AFTER dispatch
        // (below) so a fully-revealed line gets a beat before the next event.
      } else if speed.interEventDelayMs > 0 {
        try? await Task.sleep(for: .milliseconds(speed.interEventDelayMs))
      }

      handleEvent(event, scenario: scenario)

      // VN-style reading pause after a committed utterance (Sim-only).
      // resume() is live Sim (LLM generation from round K+1), so it gets the
      // same beat as run() — not replay, which paces on its own clock.
      if case .agentOutput = event {
        await holdAfterAgentOutput(script: readingScript)
      }
    }

    await finalizeRun(llm: llm)
  }

  // MARK: - Event Handling

  // internal (not private) to allow direct unit testing via @testable import
  func handleEvent(_ event: SimulationEvent, scenario: Scenario) {  // swiftlint:disable:this cyclomatic_complexity function_body_length

    switch event {
    case .roundStarted(let round, let total):
      handleRoundStarted(round: round, total: total)
    case .roundCompleted(let round, let newScores):
      handleRoundCompleted(round: round, scores: newScores)
    case .phaseStarted(let phaseType, let phasePath):
      currentPhaseType = phaseType
      currentPhasePath = phasePath
      logEntries.append(LogEntry(kind: .phaseStarted(phaseType: phaseType)))
    case .phaseCompleted(let phaseType, let phasePath):
      // Pop `currentPhasePath` back one level when the inner sub-phase's
      // completion arrives (path matches AND count > 1) — so a subsequent
      // event fired before the next `.phaseStarted` isn't mis-attributed to
      // the stale inner path (#143). `currentPhaseType` intentionally still
      // lingers: consumers that need exact phaseType attribution already
      // read the event's own `phaseType` per `.claude/rules/engine.md`.
      if currentPhasePath == phasePath, phasePath.count > 1 {
        currentPhasePath?.removeLast()
      }
      // Contradiction badge (#916): evaluate only once the whole choose
      // phase has completed — every action of the round is then in the
      // buffers, so a first-appearance action can never fire a premature
      // full-contradiction verdict. Event consumption is paced by the
      // reading-hold loop, so this beat is also the display beat: the last
      // pairing row is already on screen and the reveal spoils nothing.
      if phaseType == .choose {
        revealContradictions(scenario: scenario)
      }
    case .simulationPaused, .conditionalEvaluated:
      // No-op — `.simulationPaused` is a runner-side acknowledgement of the
      // user-initiated pause flow; the UI already reflects `isPaused` set
      // synchronously by the pause button. Background-driven suspend uses
      // the SuspendController path instead.
      //
      // `.conditionalEvaluated` is visible via the bracketing
      // `.phaseStarted(.conditional, _)` + inner sub-phase events; UI
      // surfacing of the condition/result pair is deferred.
      break
    case .languageMismatch(let agent, let detected, let expected):
      // ADR-010 §"Out of Scope" / #401 — informational drift surface.
      // First event sets the one-shot toast; subsequent events only
      // increment the cumulative count (surfaced post-run). Toast does NOT
      // re-fire within the same `run()` cycle even after dismissal —
      // burst-pattern noise suppression. Gating on `count == 0`
      // (pre-increment) rather than `pendingLanguageMismatchToast == nil`
      // is load-bearing: after dismissal, pending is nil but count is
      // already > 0, so the next event correctly skips the toast set.
      let isFirstEvent = languageMismatchCount == 0
      languageMismatchCount += 1
      if isFirstEvent {
        pendingLanguageMismatchToast = LanguageMismatchToast(
          agent: agent, detected: detected, expected: expected)
      }
    case .turnSkipped(let agent, let phaseType, let cause):
      // ADR-021 D5 — a contained LLM turn failure. Count it (D6 aggregate)
      // and narrate it live, one line per skip. `cause` is the engine's
      // English diagnostic (same register as `.error`); it is NOT rendered
      // (the log line is localized from `agent` + `phaseType`), only logged
      // for diagnostics. The `.debug` line interpolates only the phase enum
      // and the engine diagnostic — no user content (the persona name is
      // deliberately omitted per the "don't Logger-interpolate agent
      // content" rule); `.debug` is also redacted in Release regardless.
      degradedTurnCount += 1
      lifecycleLogger.debug(
        "turn skipped in \(phaseType.rawValue) — \(cause)")
      logEntries.append(
        LogEntry(kind: .turnSkipped(agent: agent, phaseType: phaseType)))
    case .agentOutput(let agent, let output, let phaseType):
      handleAgentOutput(agent: agent, output: output, phaseType: phaseType)
    case .agentOutputStream(let agent, let primary, let thought):
      #if DEBUG
        detectSilentStreamReIssue(agent: agent, primary: primary)
      #endif
      handleAgentOutputStream(agent: agent, primary: primary, thought: thought)
    case .simulationCompleted:
      isCompleted = true
      // #401 — append a one-line completion report when adherence
      // drift was observed during the run. Header stays clean during
      // the run (drift count would be context-free at-a-glance);
      // surfacing the cumulative count at the end is the post-run
      // review moment where the number is useful.
      if languageMismatchCount > 0 {
        let text = String(
          format: String(localized: "Language mismatch ×%lld"),
          languageMismatchCount)
        logEntries.append(LogEntry(kind: .summary(text: text)))
      }
    case .roundCheckpoint(let state):
      persistCheckpoint(state)
    case .error(let simError):
      // A `.cancelled` arriving while the run is explicitly paused OR is a
      // resumed run is the teardown signal (the user navigated away / switched
      // tabs), not a failure. Suppress it so `errorMessage` stays nil and the
      // terminal ladder leaves the run resumable (`.paused`) instead of
      // overwriting it with `.failed`. `isResumedRun` widens the guard beyond
      // `didPersistPaused` because a resumed run torn down mid-flight was never
      // re-paused (so `didPersistPaused` is false) yet must stay resumable from
      // its latest checkpoint. Real errors (any non-`.cancelled`) still surface.
      if didPersistPaused || isResumedRun, simError == .cancelled { break }
      // Use `localizedDescription` (LocalizedError-conforming) for both
      // the alert text and the log entry — `"\(simError)"` would render
      // the enum case repr (e.g. "retriesExhausted"), which is debug
      // output, not user-facing copy.
      let message = simError.localizedDescription
      errorMessage = message
      logEntries.append(LogEntry(kind: .error(message)))
    case .inferenceStarted(let agent):
      thinkingAgents.insert(agent)
      // A new inference starts: any leftover snapshot from a previous
      // attempt (parse retry, different agent) must not linger in the UI,
      // and the streaming reveal counter restarts from zero so a stale
      // position can't seed this inference's committed row.
      streamingSnapshot = nil
      streamingRevealedChars = 0
      #if DEBUG
        inflightInferenceAttempts[agent, default: 0] += 1
        let attempt = inflightInferenceAttempts[agent] ?? 0
        // Noise-gate: only log retries (attempt ≥ 2). First attempts are every
        // turn and would drown the signal.
        if attempt >= 2 {
          Self.streamingDiagLogger.info(
            "retry agent=\(agent, privacy: .public) attempt=\(attempt)"
          )
        }
        // Clear raw-primary tracker so the retry's new stream doesn't
        // double-log as a streamReset — parse retry is owned by the
        // attempt counter above; streamReset measures the *silent*
        // re-issue path (suspend-resume) that bypasses this event.
        lastRawStreamingPrimary[agent] = nil
      #endif
    case .inferenceCompleted(let agent, let seconds, let tokens):
      thinkingAgents.remove(agent)
      handleInferenceCompleted(durationSeconds: seconds, tokenCount: tokens)
    default:
      // Lifecycle tier-1 forward: the D2 no-default exhaustiveness pin lives in
      // `handleOutputEvent` (ADR-022 §D2 tiered pattern), NOT this arm — a new
      // SimulationEvent case compile-breaks there, not here.
      handleOutputEvent(event)
    }
  }

  /// Terminal tier of the `handleEvent` → `handleOutputEvent` two-tier switch
  /// (ADR-022 P1/D2). Each code-phase arm updates UI state; **persistence is
  /// collapsed** into the single post-switch `persistCodePhaseEventIfNeeded`
  /// call (ADR-022 P4/D3) instead of a per-arm construction.
  ///
  /// **No-default exhaustive** over `SimulationEvent` (ADR-022 D2): the
  /// non-code-phase remainder is an explicitly-listed `break` arm, so a new
  /// event case fails to compile here until a decision is made — replacing the
  /// former `default: break` that let a new case silently no-op.
  private func handleOutputEvent(_ event: SimulationEvent) {
    switch event {
    case .scoreUpdate(let newScores):
      handleScoreUpdate(scores: newScores)
    case .elimination(let agent, let voteCount):
      handleElimination(agent: agent, voteCount: voteCount)
    case .assignment(let agent, let value):
      // Accumulate for the wolf ground-truth derivation at the first vote
      // reveal (#915). Assign phases run before any vote, so this is populated
      // by the time the prediction is scored.
      predictionAssignments[agent] = value
      logEntries.append(LogEntry(kind: .assignment(agent: agent, value: value)))
    case .sharedAssignment(let value):
      handleSharedAssignment(value: value)
    case .summary(let text):
      logEntries.append(LogEntry(kind: .summary(text: text)))
    case .narration(let text):
      // ADR-005 (App Store content safety): narration is free LLM prose about
      // the agents, so it MUST be `ContentFilter`-rewritten before display —
      // do NOT copy the `.summary` arm above, which renders raw because its
      // text is deterministic template / scoring output. Filtered here at the
      // VM boundary so every live consumer of this `LogEntry` shows safe text.
      logEntries.append(LogEntry(kind: .narration(text: contentFilter.filter(text))))
    case .voteResults(let votes, let tallies):
      // Keep the latest tallies for the final-ranking card's vote-only
      // ranking (#868); last-wins matches `scores`' full-replace semantics.
      voteResults = tallies
      logEntries.append(LogEntry(kind: .voteResults(votes: votes, tallies: tallies)))
    case .pairingResult(let agent1, let act1, let agent2, let act2):
      logEntries.append(
        LogEntry(
          kind: .pairingResult(
            agent1: agent1, action1: act1, agent2: agent2, action2: act2
          )))
    case .eventInjected(let injected):
      // Log even on miss (`injected == nil`) so past-results timelines and
      // Markdown export distinguish "phase didn't run" from "phase ran and
      // rolled a miss". Persistence of the miss is handled by the collapse.
      logEntries.append(LogEntry(kind: .eventInjected(event: injected)))
    // Non-code-phase events: handled upstream in `handleEvent`'s lifecycle
    // tier (they never reach here via the `default:` forward) or intentionally
    // not projected by this surface (`relationshipUpdate` has no live display
    // in v1). Listed explicitly — no `default:` — so a new case forces a
    // decision (ADR-022 D2).
    case .roundStarted, .roundCompleted, .phaseStarted, .phaseCompleted,
      .agentOutput, .agentOutputStream, .relationshipUpdate,
      .conditionalEvaluated, .simulationCompleted, .roundCheckpoint,
      .simulationPaused, .error, .inferenceStarted, .inferenceCompleted,
      .languageMismatch, .turnSkipped:
      break
    }
    persistCodePhaseEventIfNeeded(event)
  }

  /// The single `SimulationEvent` → `code_phase_events` persist path (ADR-022
  /// P4/D3), replacing the eight ad-hoc constructions previously scattered
  /// across `handleOutputEvent` arms and `handleSharedAssignment`.
  ///
  /// The payload and its fallback phase are non-nil for exactly the same case
  /// set (the paired-nil invariant of ``CodePhaseEventPayload/init(event:)`` /
  /// ``SimulationEvent/defaultCodePhaseType``), so both bind — the fallback is
  /// never force-unwrapped. The persisted `phaseType` prefers the live
  /// `currentPhaseType` (tracked from `.phaseStarted`); the per-event fallback
  /// matters for `.summary`, which fires from both `SummarizeHandler` and
  /// scoring logics like `wordwolf_judge` — a hard-coded phase would mis-bucket
  /// the judge verdict in exports.
  private func persistCodePhaseEventIfNeeded(_ event: SimulationEvent) {
    guard let payload = CodePhaseEventPayload(event: event),
      let fallbackPhase = event.defaultCodePhaseType
    else { return }
    // `.summary` also fires for validator warnings (before the first round
    // starts, currentRound == 0) and early-termination (after the round loop
    // exits). Export intentionally drops the pre-round warnings — they are
    // diagnostic, not part of the scenario's narrative.
    if case .summary = event, currentRound == 0 { return }
    persistCodePhaseEvent(
      phaseType: currentPhaseType?.rawValue ?? fallbackPhase.rawValue,
      payload: payload)
  }

  private func handleRoundStarted(round: Int, total: Int) {
    currentRound = round
    totalRounds = total
    // A declaration only ever contradicts actions of its own round (#916).
    declaredIntents = [:]
    chooseRawActions = [:]
    logEntries.append(LogEntry(kind: .roundStarted(round: round, totalRounds: total)))
  }

  private func handleRoundCompleted(round: Int, scores newScores: [String: Int]) {
    scores = newScores
    logEntries.append(LogEntry(kind: .roundCompleted(round: round, scores: newScores)))
  }

  /// Runs the #916 contradiction check for every agent that declared this
  /// round, badges the declaration row, and appends the 🃏 reveal line.
  /// Persona-roster iteration keeps multi-agent reveal order deterministic.
  /// Idempotent per declaration row (badged ids are skipped), so a second
  /// choose phase in the same round cannot double-reveal.
  private func revealContradictions(scenario: Scenario) {
    guard !declaredIntents.isEmpty else { return }
    let options = ContradictionDetectionLogic.chooseOptions(in: scenario.phases)
    guard !options.isEmpty else { return }
    for persona in scenario.personas {
      guard let declaration = declaredIntents[persona.name],
        !contradictionBadgedEntryIDs.contains(declaration.entryID),
        ContradictionDetectionLogic.isContradiction(
          declared: declaration.value,
          actions: chooseRawActions[persona.name] ?? [],
          options: options)
      else { continue }
      contradictionBadgedEntryIDs.insert(declaration.entryID)
      logEntries.append(LogEntry(kind: .contradictionRevealed(agent: persona.name)))
    }
  }

  private func handleAgentOutput(agent: String, output: TurnOutput, phaseType: PhaseType) {
    #if DEBUG
      // Turn-commit: emit final tally if it required retries, then clear.
      // The clear has to sit here (not in `.inferenceCompleted`) because
      // LLMCaller emits `.inferenceCompleted` per attempt; `.agentOutput`
      // is the unique "this turn is done" signal.
      if let total = inflightInferenceAttempts[agent], total > 1 {
        Self.streamingDiagLogger.info(
          "committed agent=\(agent, privacy: .public) totalAttempts=\(total)"
        )
      }
      inflightInferenceAttempts[agent] = nil
      lastRawStreamingPrimary[agent] = nil
    #endif
    let filtered = contentFilter.filter(output)
    // Snapshot-vs-canonical divergence telemetry: compare the last
    // streamed snapshot against the canonical parser result for the
    // same inference. A mismatch here means the partial extractor
    // showed the user something that the canonical parse later
    // contradicted — exactly the failure mode the critic flagged.
    // Debug-level so it stays available for future investigation
    // without polluting production logs.
    //
    // Distinct from the DEBUG `detectSilentStreamReIssue` diagnostic
    // (Hyp A′, runs at the `handleEvent` dispatch site): that
    // one measures *silent stream re-issue* via raw-primary
    // monotonicity across events. This check measures
    // *snapshot-vs-canonical* agreement at commit, is gated on
    // `streamingSnapshot != nil`, and is therefore silenced under
    // `.instant` (snapshot stays nil per ADR-002 §11.2 Axis ③). The
    // dispatch-site diagnostic runs above the `.instant` gate and
    // fires for all speeds — they do not substitute for one another.
    if let snapshot = streamingSnapshot, snapshot.agent == agent {
      let canonicalPrimary = filtered.primaryText(for: phaseType) ?? ""
      // Compare against the *decorated* snapshot. `PartialOutputExtractor`
      // stores the bare primary (e.g. the vote value without the `→ ` arrow),
      // while `primaryText(for:)` returns the decorated form — so for vote
      // `"→ X".hasPrefix("X")` was structurally always false and fired a
      // spurious divergence log every turn (#615). Decorating via the #613
      // single source of truth restores the prefix invariant. Use the
      // commit-time `phaseType` parameter (not `snapshot.phaseType`): the
      // canonical parse is authoritative for the phase this turn committed
      // as, and a mid-turn snapshot can be stale.
      let decoratedSnapshot = ScenarioConventions.decoratePrimary(
        snapshot.primary, for: phaseType)
      if !canonicalPrimary.hasPrefix(decoratedSnapshot) {
        lifecycleLogger.debug(
          "stream divergence: agent=\(agent, privacy: .public), snapshot primary \(decoratedSnapshot.prefix(40), privacy: .public) is not a prefix of canonical \(canonicalPrimary.prefix(40), privacy: .public)"
        )
      }
    }
    // If a snapshot was active for this agent the user has already watched
    // the primary stream live up to `streamingRevealedChars`. Hand that
    // position off as the committed row's reveal seed so it continues typing
    // the unrevealed tail at cps instead of snapping (see
    // `handoffSeed(forEntryId:)` / `effectiveCharsPerSecond(forEntryId:)`).
    //
    // Note: `contentFilter.filter(output)` above may rewrite the primary, so
    // the committed text can differ from what streamed; the seed is clamped
    // to the committed length on the View side. Filter rewrites are rare and
    // already surface via divergence telemetry; a filter-shrunk primary may
    // early-reveal the thought section — accepted, and any further transition
    // UX on that edge belongs to the #133 streaming-display redesign.
    let wasStreamed = streamingSnapshot?.agent == agent
    let handoffSeed = wasStreamed ? streamingRevealedChars : 0
    streamingSnapshot = nil
    let entry = LogEntry(
      kind: .agentOutput(agent: agent, output: filtered, phaseType: phaseType))
    logEntries.append(entry)
    // Contradiction detection (#916) records from the RAW output, not
    // `filtered`: declared_intent / action are machine tokens the filter
    // could in principle rewrite, and detection must match what the agent
    // actually produced. Neither token is displayed from these buffers.
    // Speak-phase gate: declared_intent is a speak-phase declaration; a
    // different phase emitting the reserved field must not re-key the
    // badge onto a non-declaration row.
    if phaseType == .speakAll || phaseType == .speakEach,
      let declared = output.fields[ContradictionDetectionLogic.declaredIntentField] {
      declaredIntents[agent] = (value: declared, entryID: entry.id)
    }
    if phaseType == .choose, let action = output.action {
      chooseRawActions[agent, default: []].append(action)
    }
    // Track the newest agentOutput so AgentOutputRow can gate the typing
    // animation to only the latest row — older rows snap to full text when
    // this id flips.
    latestAgentOutputId = entry.id
    // The new latest row has not revealed yet — clear the completion latch so
    // an adopt re-projection mid-reveal doesn't wrongly treat it as static
    // (ADR-017 Phase B; see ``latestRowRevealCompleted``).
    latestRowRevealCompleted = false
    if wasStreamed { streamingHandoffChars[entry.id] = handoffSeed }
    // Capture the reveal inputs so `holdAfterAgentOutput` can hold the next
    // turn until this row finishes typing from `handoffSeed` (bug 2). Uses
    // the global `showAllThoughts` (the per-row chevron can drift it slightly
    // mid-flight — accepted, same heuristic as ReplayViewModel's floor).
    let segments = filtered.revealedSegments(
      for: phaseType, includeThought: showAllThoughts)
    lastAgentOutputReveal = AgentOutputReveal(
      seed: handoffSeed, primary: segments.primary, thought: segments.thought)
    // The reveal handoff has been recorded; clear the running counter so the
    // next agent's row can never inherit this one's position.
    streamingRevealedChars = 0
    // Reading-pause length: grapheme count of the committed (filtered) primary
    // text. Thought is excluded — see ``PlaybackSpeed/readingDwell(displayLength:)``.
    lastAgentOutputDisplayLength = (filtered.primaryText(for: phaseType) ?? "").count
    thinkingAgents.remove(agent)
    persistTurnRecord(agent: agent, output: output, phaseType: phaseType)
  }

  /// Reading-pause held after an agent utterance has been dispatched to the
  /// log, before the consume loop pulls the next event — the visual-novel
  /// "auto mode" beat for the **live Sim** (replay paces turns on its own
  /// ``ReplayViewModel`` clock, so this is Sim-only; see
  /// ``PlaybackSpeed/readingDwell(displayLength:)``).
  ///
  /// **Typing-synced hold.** Since the reveal-position handoff (bug 2) the
  /// committed row no longer snaps to full at `.agentOutput` — it continues
  /// typing the unrevealed tail (and `inner_thought`) from its handoff seed
  /// at cps. So this pause is `max(readingDwell, remainingTyping)`: when the
  /// remaining typing outlasts the reading dwell (a long line at a slow cps,
  /// whether it streamed or — on the streaming-off path — types from zero),
  /// the next turn waits for the typing to finish. That makes the tail / the
  /// thought reveal smoothly to completion instead of snapping when a fast
  /// next inference commits and flips this row off `isLatest`. The remaining
  /// typing is sized by ``remainingTypingDurationMs(seed:primary:thought:charsPerSecond:)``
  /// from the segments captured at commit (``lastAgentOutputReveal``) — it
  /// mirrors `AgentOutputRow`'s reveal loop exactly, so the two cannot drift.
  /// On long lines this paces the whole Sim to the typing rate; the cost is
  /// accepted (the user chose a slow cps for readability).
  ///
  /// Reads `speed` at call time so a mid-run speed change applies on the next
  /// pause; `.instant` yields `.zero` (no dwell, no typing) and is skipped.
  /// `script` is the run's reading-density class (from
  /// `scenario.engineLanguage`) — passed in rather than stored because it is
  /// constant for a run and the consume loop already holds the scenario.
  /// `try?` swallows a teardown/cancel during the sleep, matching the existing
  /// `interEventDelayMs` sleep; **teardown** cancels the run task so the sleep
  /// aborts promptly. **Pause** does not cancel the loop (it parks the suspend
  /// controller), so an in-flight hold runs to completion before the loop
  /// reaches the park point — benign (status is persisted synchronously in
  /// `pauseSimulation`, and the displayed row keeps typing via its own task),
  /// but since this path drops `readingDwell`'s per-tier cap a long line at a
  /// slow cps can idle the loop for tens of seconds after a pause.
  private func holdAfterAgentOutput(script: ReadingScript) async {
    let dwell = speed.readingDwell(
      displayLength: lastAgentOutputDisplayLength, script: script)
    let hold = max(dwell, pendingTypingHold)
    guard hold > .zero else { return }
    try? await Task.sleep(for: hold)
  }

  /// Time the just-committed row still needs to type from its handoff seed —
  /// `.zero` when nothing is pending or playback is `.instant`. Drives the
  /// typing-synced portion of ``holdAfterAgentOutput(script:)``; exposed
  /// (`internal`) so the hold decision is unit-testable without a wall-clock
  /// sleep (view-testing rule 4).
  var pendingTypingHold: Duration {
    guard let reveal = lastAgentOutputReveal, let cps = speed.charsPerSecond
    else { return .zero }
    return .milliseconds(
      remainingTypingDurationMs(
        seed: reveal.seed, primary: reveal.primary, thought: reveal.thought,
        charsPerSecond: cps))
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
  #if DEBUG
    /// Hyp A' signal: detect stream restart that didn't go through
    /// `.inferenceStarted` (LLMCaller `consumeStreamWithSuspendRetry`
    /// re-issue path on `.suspended`).
    ///
    /// Two sub-patterns — normal appending never hits either:
    ///  - "diverge" — new is neither an extension nor a prefix-shrink
    ///    of existing. Fires when the re-issued stream produces
    ///    different text (non-deterministic LLM).
    ///  - "shrink"  — new is a strict prefix of existing (`new.count <
    ///    existing.count` AND `existing.hasPrefix(new)`). Fires on
    ///    the first chunk of a re-issue when Gemma is deterministic
    ///    enough to regenerate the same tokens — content goes
    ///    backwards to "H" / "He" / ... before climbing back.
    /// Partial parser shouldn't emit non-monotone primaries within a
    /// single stream iteration, so shrink is a strong re-issue signal.
    ///
    /// Uses raw (pre-ContentFilter) primary so filter rewrites like
    /// `"fuck" → "***"` aren't mistaken for resets.
    ///
    /// Distinct from the "stream divergence" debug log in
    /// ``handleAgentOutput(agent:output:phaseType:)`` — see the comment
    /// block at that call site for the full comparison. Summary: that
    /// one checks snapshot-vs-canonical at commit (silenced under
    /// `.instant`); this one checks raw-primary monotonicity at the
    /// dispatch site (runs for all speeds).
    private func detectSilentStreamReIssue(agent: String, primary: String?) {
      guard let newPrimary = primary, !newPrimary.isEmpty else { return }
      if let existing = lastRawStreamingPrimary[agent] {
        let diverge =
          !newPrimary.hasPrefix(existing) && !existing.hasPrefix(newPrimary)
        let shrink =
          newPrimary.count < existing.count && existing.hasPrefix(newPrimary)
        if diverge || shrink {
          let kind = diverge ? "diverge" : "shrink"
          Self.streamingDiagLogger.info(
            "streamReset agent=\(agent, privacy: .public) type=\(kind, privacy: .public) oldLen=\(existing.count) newLen=\(newPrimary.count)"
          )
        }
      }
      lastRawStreamingPrimary[agent] = newPrimary
    }
  #endif

  private func handleAgentOutputStream(
    agent: String, primary: String?, thought: String?
  ) {
    guard FeatureFlags.realtimeStreamingEnabled else { return }
    // `.instant` playback means "do not animate reveal in any form"
    // (ADR-002 §11.2 Axis ③). Short-circuit at the event layer — with
    // no snapshot set, the thinking indicator persists until the
    // canonical `.agentOutput` commit and the full output appears at
    // once, matching the flag-off baseline. Accepted trade-offs:
    // (a) `.instant` users lose the live snapshot-vs-canonical
    // divergence check in `handleAgentOutput` — it is gated on
    // `streamingSnapshot != nil`, which never holds under `.instant`.
    // The upstream DEBUG `detectSilentStreamReIssue` diagnostic runs
    // at the `handleEvent` dispatch site and is unaffected. Coverage
    // for the lost check: non-`.instant` users + unit/integration
    // tests, per ADR-002 §11.2. (b) A mid-turn speed change from
    // `.normal` / `.slow` / `.fast` → `.instant` leaves the existing
    // snapshot in place until commit — this is an accepted limitation,
    // not a supported toggle-responsiveness contract.
    guard speed != .instant else { return }
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

  private func handleSharedAssignment(value: String) {
    // Shared お題 assigned to every agent (`assign` target: all, #939). One
    // line, no agent attribution. Deliberately NOT written to
    // `predictionAssignments`: that is word-wolf per-agent ground truth (#915),
    // and a shared topic has no minority holder to derive a wolf from.
    // Persistence is handled by `handleOutputEvent`'s post-switch collapse.
    logEntries.append(LogEntry(kind: .sharedAssignment(value: value)))
  }

  private func handleElimination(agent: String, voteCount: Int) {
    eliminated[agent] = true
    // Capture the count at elimination time so the final-ranking card's
    // survival framing shows each eliminated agent's own round tally (#868).
    eliminationVotes[agent] = voteCount
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
    simId: String, scenario: Scenario, state: SimulationState, llm: any LLMService,
    scenarioCategorySnapshot: String?
  ) async {
    do {
      let stateJSON = try JSONEncoder().encode(state)
      // Snapshot the scenario that actually ran by re-serializing the live
      // domain object — NOT by re-fetching the persisted record by id. The
      // domain object is always in hand here, so the snapshot is faithful to
      // this run and independent of whether/when the scenario row is later
      // edited or deleted. Read paths reconstruct from this when `scenarioId`
      // is nil (scenario deleted) or to avoid edit-drift while it still exists.
      // The gallery category (#748) is the exception: it is not on the domain
      // object (it's gallery metadata, not in the YAML), so the launch callsite
      // threads it in as `scenarioCategorySnapshot` from the `ScenarioRecord` it
      // already holds — still captured here, still no refetch-by-id.
      let scenarioYamlSnapshot = ScenarioSerializer().serialize(scenario)
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
        llmBackend: llm.backendIdentifier,
        scenarioYamlSnapshot: scenarioYamlSnapshot,
        scenarioNameSnapshot: scenario.name,
        scenarioCategorySnapshot: scenarioCategorySnapshot
      )
      try await offMain { [simulationRepository] in
        try simulationRepository.save(record)
      }
    } catch {
      lifecycleLogger.error(
        "Failed to create simulation record: \(String(describing: error), privacy: .public)")
    }
  }

  private func startPersistenceConsumer() {
    let (stream, continuation) = AsyncStream<TurnRecord>.makeStream()
    persistenceContinuation = continuation
    let repo = turnRepository
    // Local-bind the (Sendable) Logger so the Task.detached closure does not
    // capture `self` across actor boundaries — same idiom as `let repo = ...`.
    let logger = lifecycleLogger
    persistenceTask = Task.detached {
      for await record in stream {
        do {
          try repo.save(record)
        } catch {
          logger.error(
            "Failed to persist turn: \(String(describing: error), privacy: .public)")
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
      // `rawOutput` stores the unfiltered LLM emission per the column's
      // documented contract. Pre-#194 this column was set to `jsonString`
      // (the parsed-and-re-encoded JSON), silently swapping the raw audit
      // trail for a parsed projection — load-bearing to fix before any
      // repair heuristic lands (would otherwise erase the LLM's actual
      // output on every successful repair). Empty-string fallback is a
      // loud production signal: a TurnRecord with rawOutput == "" means
      // wiring is broken (`output.rawText` was nil), not that the model
      // emitted nothing.
      let rawOutput = output.rawText ?? ""
      if output.rawText == nil {
        // Defence-in-depth: logs in Release too so a TestFlight regression
        // that drops `rawText` wiring surfaces in production logs (not just
        // debug builds). The condition is expected to be unreachable —
        // `LLMCaller` always populates `rawText` via `JSONResponseParser`.
        lifecycleLogger.error(
          "rawText nil on agentOutput for agent=\(agent, privacy: .public); audit trail will be empty"
        )
      }
      turnSequence += 1
      let record = TurnRecord(
        id: UUID().uuidString,
        simulationId: simId,
        roundNumber: currentRound,
        phaseType: phaseType.rawValue,
        agentName: agent,
        rawOutput: rawOutput,
        parsedOutputJSON: jsonString,
        sequenceNumber: turnSequence,
        phasePathJSON: encodedCurrentPhasePath(),
        createdAt: Date()
      )
      persistenceContinuation?.yield(record)
    } catch {
      lifecycleLogger.error(
        "Failed to encode turn output: \(String(describing: error), privacy: .public)")
    }
  }

  /// JSON-encodes `currentPhasePath` as a compact `[Int]` (e.g. `"[1,0]"`)
  /// for the `phasePathJSON` column, or returns `nil` when no phase is active
  /// (pre-first-`.phaseStarted` events). JSONEncoder on a small `[Int]` can't
  /// realistically fail; a throw here is treated as "unknown path" so a rare
  /// encode failure doesn't lose the rest of the row.
  private func encodedCurrentPhasePath() -> String? {
    guard let path = currentPhasePath else { return nil }
    guard let data = try? JSONEncoder().encode(path),
      let json = String(data: data, encoding: .utf8)
    else { return nil }
    return json
  }

  private func startCodePhasePersistenceConsumer() {
    // If no repository was injected, skip starting the consumer — yields
    // from `persistCodePhaseEvent` become no-ops because the continuation
    // stays nil. This keeps existing call sites (pre-#92 constructors) working.
    guard let codePhaseRepo = codePhaseEventRepository else { return }
    let (stream, continuation) = AsyncStream<CodePhaseEventRecord>.makeStream()
    codePhasePersistenceContinuation = continuation
    // Local-bind the (Sendable) Logger so the Task.detached closure does not
    // capture `self` across actor boundaries — same idiom as `let repo = ...`.
    let logger = lifecycleLogger
    codePhasePersistenceTask = Task.detached {
      for await record in stream {
        do {
          try codePhaseRepo.save(record)
        } catch {
          logger.error(
            "Failed to persist code-phase event: \(String(describing: error), privacy: .public)")
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
        lifecycleLogger.error("Failed to stringify code-phase payload JSON")
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
        phasePathJSON: encodedCurrentPhasePath(),
        createdAt: Date()
      )
      continuation.yield(record)
    } catch {
      lifecycleLogger.error(
        "Failed to encode code-phase payload: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: - Viewer prediction (#915)

  /// A prediction captured at vote-phase start, awaiting the tally to score it.
  private struct PendingPrediction {
    let question: ViewerPredictionLogic.Question
    let picked: String
    /// Roster captured at prompt time — the `topVote` scoring ranks over this.
    let candidates: [String]
  }

  /// Drives the viewer-prediction feature off the run loop (#915). Two events
  /// matter, and interception happens BEFORE the votes are shown so the outcome
  /// isn't spoiled:
  ///
  /// - **`.phaseStarted(.vote)`** — the first vote phase of a fresh run. Latches
  ///   the run's single prediction opportunity, then (if foreground-visible)
  ///   pauses the loop to present the sheet and captures the pick into
  ///   `pendingPrediction`. This fires *before* any agent casts a vote
  ///   (`SimulationRunner` emits `phaseStarted` before the handler runs), so the
  ///   individual votes don't leak the answer.
  /// - **`.voteResults`** — the tally. Scores the captured pick against the
  ///   reveal-moment ground truth (wolf from `.assignment` events; `#1` from
  ///   these tallies) and persists it (answered predictions only).
  ///
  /// The latch is set BEFORE the visibility check (even on skip / not-presentable)
  /// so a parked/backgrounded first vote consumes the opportunity and a later
  /// vote is never asked. `run()` only — a resumed run never asks.
  ///
  /// Internal (not `private`) so a unit test can drive it directly (ADR-009 /
  /// `.claude/rules/view-testing.md`): feed `.phaseStarted(.vote)` (resolving the
  /// sheet by polling `predictionPrompt`), then `.voteResults`.
  func handleViewerPredictionEvent(
    event: SimulationEvent, scenario: Scenario
  ) async {
    switch event {
    case .phaseStarted(let phaseType, _) where phaseType == .vote:
      await presentPredictionAtVoteStart(scenario: scenario)
    case .voteResults(_, let tallies):
      await scorePendingPrediction(tallies: tallies)
    default:
      break
    }
  }

  private func presentPredictionAtVoteStart(scenario: Scenario) async {
    guard
      !hasAttemptedPrediction,
      FeatureFlags.viewerPredictionEnabled,
      predictionRepository != nil,
      simulationId != nil,
      let question = ViewerPredictionLogic.question(for: scenario.phases)
    else { return }

    // Latch BEFORE the visibility check so a parked/backgrounded first vote
    // still consumes the run's one opportunity (a later vote is never asked).
    hasAttemptedPrediction = true

    // Present only when the sim screen is foreground-visible; a parked
    // (ADR-017 Phase B) or backgrounded run skips this run's prediction.
    guard isViewVisible, !isAppBackgrounded else { return }

    let candidates = activePredictionCandidates(scenario: scenario)
    // Need at least two agents to make a prediction meaningful.
    guard candidates.count >= 2 else { return }

    let resolution = await presentPrediction(
      ViewerPredictionPrompt(question: question, candidates: candidates))

    // Skip / timeout / navigate-away leave no pending pick and no row.
    guard case .predicted(let picked) = resolution else { return }
    pendingPrediction = PendingPrediction(
      question: question, picked: picked, candidates: candidates)
  }

  private func scorePendingPrediction(tallies: [String: Int]) async {
    guard
      let pending = pendingPrediction,
      let predictionRepository,
      let simId = simulationId
    else { return }
    pendingPrediction = nil

    let actual: String? = {
      switch pending.question {
      case .wolf:
        return ViewerPredictionLogic.wolf(from: predictionAssignments)
      case .topVote:
        return ViewerPredictionLogic.topVote(
          tallies: tallies, roster: pending.candidates)
      }
    }()
    // Ground truth not uniquely derivable (e.g. an ambiguous minority) → leave
    // the run unscored rather than record a coin-flip.
    guard let actual else { return }

    let streak = await persistPrediction(
      repository: predictionRepository, simulationId: simId,
      question: pending.question, predicted: pending.picked, actual: actual)
    predictionOutcome = PredictionOutcome(
      isHit: ViewerPredictionLogic.isHit(predicted: pending.picked, actual: actual),
      streak: streak)
  }

  /// Active (non-eliminated) agent names — the choosable roster. At the first
  /// vote nobody is eliminated yet, so this is the full cast.
  private func activePredictionCandidates(scenario: Scenario) -> [String] {
    scenario.personas.map(\.name).filter { !(eliminated[$0] ?? false) }
  }

  /// Presents the sheet and suspends until the viewer resolves it.
  private func presentPrediction(
    _ prompt: ViewerPredictionPrompt
  ) async -> ViewerPredictionSheet.Resolution {
    await withCheckedContinuation { continuation in
      predictionContinuation = continuation
      predictionPrompt = prompt
    }
  }

  /// Resolves a pending prediction sheet exactly once — called by the sheet's
  /// `onResolve` and by `setViewVisible(false)` (navigate-away safety net). A
  /// no-op when nothing is pending.
  func resolvePrediction(_ resolution: ViewerPredictionSheet.Resolution) {
    guard let continuation = predictionContinuation else { return }
    predictionContinuation = nil
    predictionPrompt = nil
    continuation.resume(returning: resolution)
  }

  /// Mirrors `SimulationView`'s on-screen state. Leaving the screen mid-sheet
  /// resolves it as a skip so no phantom sheet resurfaces on return.
  func setViewVisible(_ visible: Bool) {
    isViewVisible = visible
    if !visible { resolvePrediction(.skipped) }
  }

  /// Writes an answered prediction off-main and returns the resulting
  /// consecutive-hit streak (0 on write failure). Awaited so the row exists and
  /// the streak is known before the run completes and the card renders.
  private func persistPrediction(
    repository: any PredictionRepository, simulationId: String,
    question: ViewerPredictionLogic.Question, predicted: String, actual: String
  ) async -> Int {
    let record = PredictionRecord(
      id: UUID().uuidString,
      simulationId: simulationId,
      questionKind: question.rawValue,
      predictedAgent: predicted,
      actualAgent: actual,
      isHit: ViewerPredictionLogic.isHit(predicted: predicted, actual: actual),
      createdAt: Date())
    let logger = lifecycleLogger
    return await Task.detached {
      do {
        try repository.save(record)
        return (try? repository.currentStreak()) ?? 0
      } catch {
        logger.error(
          "Failed to persist prediction: \(String(describing: error), privacy: .public)")
        return 0
      }
    }.value
  }

  // MARK: - Test Seams

  /// Initializes persistence without invoking `run()`, so unit tests can
  /// exercise `handleEvent` directly and assert DB contents. Pair with
  /// `finishPersistenceForTest()` to drain both queues before assertions.
  internal func beginPersistenceForTest(simulationId: String) {
    self.simulationId = simulationId
    turnSequence = 0
    currentPhaseType = nil
    currentPhasePath = nil
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
      // Resolve via the run's own snapshot (faithful to what ran, and works
      // for orphaned runs whose scenario was deleted); falls back to the live
      // scenario only for pre-v7 runs without a snapshot.
      guard
        let sim = try simulationRepository.fetchById(simId),
        let scenario = try ScenarioSnapshotResolver.resolve(
          for: sim, liveLookup: scenarioRepository.fetchById)
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

  /// Persists a round-boundary checkpoint (full `SimulationState` + the
  /// just-completed `currentRound`) so a paused run can resume from the next
  /// round. `currentPhaseIndex` is always `0`: round-boundary continuation
  /// re-enters at the top of the next round, so the phase index is not a resume
  /// marker here and PR1b's resume derives `startRound = currentRound + 1`.
  /// Encodes synchronously on the MainActor (capturing the value) then writes
  /// off-main. This does not lose-update against the `.paused` status write:
  /// both `updateState` and `updateStatus` are full-row read-modify-write
  /// transactions, and `DatabaseWriter` serializes write transactions (and the
  /// in-transaction `fetchOne` reads the latest committed row), so whichever
  /// commits second preserves the other's column.
  private func persistCheckpoint(_ state: SimulationState) {
    guard let simId = simulationId else { return }
    let json: String
    do {
      json = String(data: try JSONEncoder().encode(state), encoding: .utf8) ?? "{}"
    } catch {
      lifecycleLogger.error(
        "Failed to encode checkpoint: \(String(describing: error), privacy: .public)")
      return
    }
    let round = state.currentRound
    Task { [simulationRepository] in
      do {
        try await offMain {
          try simulationRepository.updateState(
            simId, stateJSON: json, currentRound: round, currentPhaseIndex: 0)
        }
      } catch {
        self.lifecycleLogger.error(
          "Failed to persist checkpoint: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// Enqueues a non-terminal status write (`.paused` / `.running`) onto a
  /// serialized chain so writes commit in call order. Because this runs on the
  /// MainActor, the `statusWriteTask` reassignment order equals the call order;
  /// each new task awaits the prior before writing, preventing a rapid
  /// pause→resume from committing `.paused` after `.running`.
  private func enqueueStatusWrite(_ status: SimulationStatus) {
    let previous = statusWriteTask
    statusWriteTask = Task {
      await previous?.value
      await persistStatus(status)
    }
  }

  /// Persists the given status to the simulation's DB row. Used both for
  /// terminal statuses (`.completed` / `.failed` / `.cancelled`) and for the
  /// resumable `.paused` / `.running` transitions driven by
  /// `pauseSimulation` / `resumeSimulation`.
  private func persistStatus(_ status: SimulationStatus) async {
    guard let simId = simulationId else { return }
    do {
      try await offMain { [simulationRepository] in
        try simulationRepository.updateStatus(simId, status: status)
      }
    } catch {
      lifecycleLogger.error(
        "Failed to update simulation status: \(String(describing: error), privacy: .public)")
    }
  }

  /// Persists the run's aggregate `.turnSkipped` count (ADR-021 D6). Called
  /// once at completion; mirrors ``persistStatus(_:)``. A write failure is
  /// non-fatal — the badge simply reads the DEFAULT 0 for this run.
  private func persistDegradedTurnCount(_ count: Int) async {
    guard let simId = simulationId else { return }
    do {
      try await offMain { [simulationRepository] in
        try simulationRepository.updateDegradedTurnCount(simId, count: count)
      }
    } catch {
      lifecycleLogger.error(
        "Failed to persist degradedTurnCount: \(String(describing: error), privacy: .public)")
    }
  }
}
