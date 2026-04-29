// swiftlint:disable file_length
// Deliberately long: ReplayViewModel owns the §4.9 playback state machine,
// the playback Task lifecycle (sleep / pause / resume with
// `remainingDelayMs` preservation per ADR-007 §3.4), pacing helpers, and
// per-event render-time state updates. Splitting into extensions across
// files would require widening `private` members (`playbackTask`,
// source iteration cursors, `remainingDelayMs`) to `internal`, which
// weakens the spec §4.2 "no persistence wiring on this path" invariant
// enforced by construction. See SimulationViewModel.swift for the same
// VM encapsulation pattern.
import Foundation

/// View model driving the DL-time demo replay screen.
///
/// Spec: `docs/specs/demo-replay-spec.md` §4.2 + §4.9.
/// Lifecycle: `docs/decisions/ADR-007.md` §3.3 + §3.4.
///
/// Consumes one or more ``ReplaySource``s via ``ReplaySource/plannedEvents()``
/// (**not** ``ReplaySource/events()``) so the VM can own `Task.sleep` and
/// honour ADR-007 §3.4's resume-from-position contract — the streaming
/// `events()` API bakes pacing into the producer task and cannot surface
/// `remainingDelayMs`.
///
/// **Persistence absence is enforced by construction (spec §4.2).** The
/// initialiser takes no repository, no DB writer, no EventStore-style
/// sink. A replayed demo cannot pollute the production `turns` /
/// `simulations` tables because the wiring to write them simply does not
/// exist on this path. Do not add a persistence parameter without
/// revising the spec.
///
/// **ContentFilter scope is narrow by design (spec §3.4, ADR-005 §5.1).**
/// Filtering is applied only to user-visible LLM-generated text:
/// `.agentOutput.output.fields.values`, `.summary.text`,
/// `.assignment.value`, `.pairingResult.action1/2`. Structured
/// identifiers (persona names in `.elimination.agent`, `.voteResults`,
/// `.scoreUpdate`) pass through unchanged — filtering them would
/// corrupt persona names that happen to contain blocklist substrings.
/// `.agentOutputStream` is not emitted by replay (spec §4.7) so is not
/// in scope.
///
/// **Sync-risk with ``SimulationViewModel``:** The live VM's
/// `handleEvent` (see `SimulationViewModel.swift`) is the canonical
/// event→view-state transform. Events that `YAMLReplaySource.plannedEvents()`
/// can currently emit — `.roundStarted`, `.phaseStarted`, `.agentOutput`,
/// `.scoreUpdate`, `.elimination`, `.summary`, `.voteResults`,
/// `.pairingResult`, `.assignment` — should mirror the live VM's
/// filtering and state-update rules. When the live VM adds filtering
/// to a new case, check whether ``YAMLReplaySource/plannedEvents()``
/// can emit it; if yes, mirror the filter here; if no, leave alone.
@Observable
@MainActor
final class ReplayViewModel {  // swiftlint:disable:this type_body_length

  // MARK: - Public state

  /// Playback state machine per spec §4.9. Observed by the host view
  /// for transition wiring (e.g. fading to the setup-complete screen
  /// on `.transitioning`).
  nonisolated enum State: Sendable, Equatable {
    /// Constructed but not yet started. ``start()`` transitions out.
    case idle
    /// Actively playing `sources[sourceIndex]` with `eventCursor` as
    /// the index into that source's `plannedEvents()` that will be
    /// published *next* (cursor = 0 means "about to publish event 0").
    case playing(sourceIndex: Int, eventCursor: Int)
    /// Paused. `remainingDelayMs` is how much of the pre-yield sleep
    /// for `plannedEvents()[eventCursor]` was still outstanding when
    /// the pause fired. On resume, the VM sleeps exactly that many
    /// milliseconds (computed at the speed *active when the pause was
    /// captured*, not the current ``playbackSpeed`` — see that
    /// property's doc-comment for the worked example) before
    /// publishing the paused event.
    ///
    /// `reason` distinguishes scene-phase auto-pauses from explicit
    /// user-driven pauses; see ``PauseReason``. The two reasons share
    /// the same payload but have different resume semantics:
    /// ``onForeground()`` resumes only `.scenePhase`; ``userResume()``
    /// resumes only `.user`. `.user` is **sticky** across scene-phase
    /// transitions (a backgrounded user-paused VM stays paused on
    /// foreground return).
    case paused(
      sourceIndex: Int, eventCursor: Int, remainingDelayMs: Int,
      reason: PauseReason)
    /// Transitioning to the setup-complete screen. ``downloadComplete()``
    /// drives this; the host view's `.transition` animation keys off
    /// state identity.
    case transitioning
  }

  /// Discriminator on ``State/paused`` distinguishing automatic
  /// scene-phase pauses from explicit user-driven pauses. Resume
  /// semantics fork on this tag — see ``onForeground()`` and
  /// ``userResume()``.
  ///
  /// Modeled as a tag on `.paused` rather than a 5th `State` case to
  /// avoid doubling transition logic for the two reasons; the
  /// resume-from-position invariant
  /// (`firstSleepOverrideMs = remainingDelayMs`) is identical for both.
  nonisolated enum PauseReason: Sendable, Equatable {
    /// App auto-paused on backgrounding. Cleared by ``onForeground()``
    /// (auto-resume).
    case scenePhase
    /// User explicitly tapped Pause. Cleared only by ``userResume()`` —
    /// scene-phase transitions never clear `.user`. Sticky-by-design so
    /// that backgrounding + foregrounding does not silently override
    /// the user's pause intent.
    case user
  }

  private(set) var state: State = .idle

  /// Most-recent `.phaseStarted.phaseType`. Drives the phase-header
  /// view's label (e.g. "発言ラウンド 1"). Reset when `start()` is
  /// invoked.
  private(set) var currentPhase: PhaseType?

  /// Most-recent `.roundStarted.round`. Paired with
  /// ``currentTotalRounds`` for the phase-header's "round N/M" label.
  private(set) var currentRound: Int?

  /// Most-recent `.roundStarted.totalRounds`. See ``currentRound``.
  private(set) var currentTotalRounds: Int?

  /// User-selectable playback speed. Initialized from
  /// ``ReplayPlaybackConfig/playbackSpeed`` and writable at runtime
  /// (Demo controlBar's Speed Menu binds directly here, mirroring
  /// ``SimulationViewModel/speed``).
  ///
  /// **Next-event reflection only.** A speed change does not interrupt
  /// the in-flight `Task.sleep`; it takes effect at the next call to
  /// ``scaledDelay(for:)``. Worst-case latency: `turnDelayMs / .slow.multiplier`
  /// = ~2400ms with the default 1200ms turn delay. Example: at
  /// `.normal`, paused with `remainingDelayMs == 600` (computed at
  /// `.normal` rate); user changes to `.slow`; the resumed event still
  /// sleeps 600ms — the new `.slow` rate applies starting at event N+1.
  /// This matches ``SimulationViewModel``'s general inter-event-sleep
  /// behavior; recompute-on-change was deferred as the simpler mirror
  /// is acceptable for the Demo screen.
  var playbackSpeed: PlaybackSpeed

  /// Filtered agent-output events in publish order. Consumed by the
  /// host view's chat-stream component (``AgentOutputRow``). The
  /// array grows append-only within a source; on source rotation
  /// (Item 4), the consumer decides whether to clear it for a fresh
  /// demo or carry over the log.
  private(set) var agentOutputs: [AgentOutputEntry] = []

  /// One rendered agent output suitable for `AgentOutputRow`.
  nonisolated struct AgentOutputEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let agent: String
    public let output: TurnOutput
    public let phaseType: PhaseType

    public init(
      id: UUID = UUID(), agent: String, output: TurnOutput, phaseType: PhaseType
    ) {
      self.id = id
      self.agent = agent
      self.output = output
      self.phaseType = phaseType
    }
  }

  // MARK: - Dependencies

  private let sources: [any ReplaySource]
  private let config: ReplayPlaybackConfig
  private let contentFilter: ContentFilter

  // MARK: - Internal state

  /// Running playback task. Cancelled on `.paused` / `.transitioning`
  /// entry. `nil` while `.idle`, `.paused`, or `.transitioning`.
  private var streamTask: Task<Void, Never>?

  /// When non-nil, the VM is currently sleeping for a pre-yield delay
  /// and this Instant names when the sleep will finish. `onBackground()`
  /// reads this to compute `remainingDelayMs` before cancelling the
  /// stream task.
  private var currentSleepDeadline: ContinuousClock.Instant?

  // MARK: - Init

  /// Constructs a replay VM.
  ///
  /// - Parameters:
  ///   - sources: Non-empty list of replay sources. Spec §5.3
  ///     fallback (zero demos playable) is a wrapper concern
  ///     (``BundledDemoReplaySource``); by the time sources reach the
  ///     VM they are already validated.
  ///   - config: Playback pacing + loop policy (spec §4.6). The VM
  ///     reads `turnDelayMs` / `codePhaseDelayMs` / `playbackSpeed`
  ///     for per-event sleeps and `loopBehaviour` / `onComplete` for
  ///     end-of-source behaviour (loop rotation lands in a follow-up
  ///     commit on this branch). `config.playbackSpeed` seeds
  ///     ``playbackSpeed``, which is the runtime-mutable knob the UI
  ///     binds against; `config` itself stays immutable.
  ///   - contentFilter: Filter instance applied to user-visible text
  ///     at render time (spec §3.4).
  ///
  /// - Note: **Spec §4.2 invariant** — no repository, no DB writer, no
  ///   EventStore-style sink parameter. Adding one requires revising
  ///   the spec.
  init(
    sources: [any ReplaySource],
    config: ReplayPlaybackConfig = .demoDefault,
    contentFilter: ContentFilter = ContentFilter()
  ) {
    self.sources = sources
    self.config = config
    self.contentFilter = contentFilter
    self.playbackSpeed = config.playbackSpeed
  }

  // MARK: - Transition methods

  /// Begins playback from the first source, first event.
  ///
  /// No-op if already playing or transitioning. Resets observable
  /// state so a second `.idle → .playing` cycle gets a clean slate.
  func start() {
    guard case .idle = state else { return }
    guard !sources.isEmpty else { return }
    agentOutputs = []
    currentPhase = nil
    currentRound = nil
    currentTotalRounds = nil
    let startIndex = 0
    state = .playing(sourceIndex: startIndex, eventCursor: 0)
    launchPlayback(sourceIndex: startIndex, startCursor: 0, firstSleepOverrideMs: nil)
  }

  /// Pauses playback at the current position with the remaining
  /// pre-yield delay captured for accurate resumption (ADR-007 §3.4).
  ///
  /// Called by the host view's `scenePhase` observer when the scene
  /// drops below `.active`. Only triggers from `.playing` — a VM
  /// already paused (either reason) stays put. In particular, a
  /// ``State/paused``(``PauseReason/user``) VM stays user-paused
  /// through the BG cycle so foreground does not auto-resume.
  func onBackground() {
    guard case .playing(let sourceIndex, let cursor) = state else { return }
    let remaining = remainingDelayMs()
    streamTask?.cancel()
    streamTask = nil
    currentSleepDeadline = nil
    state = .paused(
      sourceIndex: sourceIndex, eventCursor: cursor, remainingDelayMs: remaining,
      reason: .scenePhase)
  }

  /// Resumes playback from the paused position, sleeping exactly the
  /// remaining delay before publishing the next event.
  ///
  /// Called by the host view's `scenePhase` observer when the scene
  /// returns to `.active`. Auto-resumes only from
  /// ``State/paused``(``PauseReason/scenePhase``). User-driven pauses
  /// (``PauseReason/user``) are sticky — the user must call
  /// ``userResume()`` to leave them.
  func onForeground() {
    guard
      case .paused(let sourceIndex, let cursor, let remainingMs, .scenePhase) =
        state
    else { return }
    state = .playing(sourceIndex: sourceIndex, eventCursor: cursor)
    launchPlayback(
      sourceIndex: sourceIndex, startCursor: cursor,
      firstSleepOverrideMs: remainingMs)
  }

  /// Pauses playback at the user's explicit request. Sticky across
  /// scene-phase transitions — ``onForeground()`` will NOT auto-resume
  /// from the resulting `.paused(.user)`; the caller must invoke
  /// ``userResume()``.
  ///
  /// Reason precedence:
  /// - From `.playing`: captures `remainingDelayMs` (mirroring
  ///   ``onBackground()``) and transitions to `.paused(.user)`.
  /// - From `.paused(.scenePhase)`: race-safety override — promotes the
  ///   reason to `.user`, preserving `remainingDelayMs`. A subsequent
  ///   ``onForeground()`` then no-ops, so the user's intent wins over
  ///   the implicit scene-phase auto-resume. The UI is normally hidden
  ///   during scene-phase pause so this branch is defense-in-depth, not
  ///   load-bearing.
  /// - From `.idle`, `.transitioning`, `.paused(.user)`: no-op.
  func userPause() {
    switch state {
    case .playing(let sourceIndex, let cursor):
      let remaining = remainingDelayMs()
      streamTask?.cancel()
      streamTask = nil
      currentSleepDeadline = nil
      state = .paused(
        sourceIndex: sourceIndex, eventCursor: cursor,
        remainingDelayMs: remaining, reason: .user)
    case .paused(let sourceIndex, let cursor, let remainingMs, .scenePhase):
      state = .paused(
        sourceIndex: sourceIndex, eventCursor: cursor,
        remainingDelayMs: remainingMs, reason: .user)
    case .idle, .transitioning, .paused(_, _, _, .user):
      return
    }
  }

  /// Resumes playback from a user-driven pause. No-op from any other
  /// state — including `.paused(.scenePhase)` (the UI is normally
  /// hidden during scene-phase pause; the scenePhase observer's
  /// ``onForeground()`` is the canonical resume path for that reason).
  func userResume() {
    guard
      case .paused(let sourceIndex, let cursor, let remainingMs, .user) = state
    else { return }
    state = .playing(sourceIndex: sourceIndex, eventCursor: cursor)
    launchPlayback(
      sourceIndex: sourceIndex, startCursor: cursor,
      firstSleepOverrideMs: remainingMs)
  }

  /// `true` when the VM is currently paused due to an explicit
  /// ``userPause()``. Drives the controlBar's Pause button icon flip
  /// (`pause.fill` ↔ `play.fill`) in the DL-time demo host view.
  /// Scene-phase pauses do NOT make this `true` — the UI is normally
  /// hidden then anyway, but the boundary is meaningful for the
  /// transient FG-redraw frame after `.scenePhase` auto-resume.
  var isUserPaused: Bool {
    if case .paused(_, _, _, .user) = state { return true }
    return false
  }

  /// Transitions to `.transitioning` and tears down the active
  /// stream task. Called when the download-complete signal arrives
  /// — the host view then owns the animated hand-off (ADR-007 §3.3
  /// case (d)).
  ///
  /// Safe from any source state except `.idle` and `.transitioning`.
  func downloadComplete() {
    switch state {
    case .idle, .transitioning:
      return
    case .playing, .paused:
      streamTask?.cancel()
      streamTask = nil
      currentSleepDeadline = nil
      state = .transitioning
    }
  }

  // MARK: - Playback task

  private func launchPlayback(
    sourceIndex: Int, startCursor: Int, firstSleepOverrideMs: Int?
  ) {
    streamTask?.cancel()
    streamTask = Task { [weak self] in
      await self?.runPlayback(
        sourceIndex: sourceIndex, startCursor: startCursor,
        firstSleepOverrideMs: firstSleepOverrideMs)
    }
  }

  private func runPlayback(
    sourceIndex startIndex: Int, startCursor: Int, firstSleepOverrideMs: Int?
  ) async {
    var sourceIndex = startIndex
    var cursor = startCursor
    var overrideMs = firstSleepOverrideMs
    while !Task.isCancelled {
      await playSource(
        sourceIndex: sourceIndex, startCursor: cursor,
        firstSleepOverrideMs: overrideMs)
      overrideMs = nil
      if Task.isCancelled { return }
      switch advanceAfterSource(currentIndex: sourceIndex) {
      case .continue(let nextIndex):
        sourceIndex = nextIndex
        cursor = 0
      case .stop:
        return
      }
    }
  }

  /// Iterates through a single source's plannedEvents starting at
  /// `startCursor`, sleeping before each event and publishing on
  /// schedule. Returns when the source ends, the task is cancelled,
  /// or the VM transitions out of `.playing(sourceIndex, ...)`.
  private func playSource(
    sourceIndex: Int, startCursor: Int, firstSleepOverrideMs: Int?
  ) async {
    let plan = sources[sourceIndex].plannedEvents()
    var cursor = startCursor
    var overrideMs = firstSleepOverrideMs
    while cursor < plan.count {
      if Task.isCancelled { return }
      let paced = plan[cursor]
      let delayMs = overrideMs ?? scaledDelay(for: paced.kind)
      overrideMs = nil
      await sleepOrYield(milliseconds: delayMs)
      if Task.isCancelled { return }
      apply(paced.event)
      cursor += 1
      // Only advance observable cursor if we're still playing (not
      // backgrounded mid-publish). Guards against a stale state
      // update stomping a just-set `.paused`.
      if case .playing(let idx, _) = state, idx == sourceIndex {
        state = .playing(sourceIndex: sourceIndex, eventCursor: cursor)
      }
    }
  }

  /// Pre-yield sleep policy for a planned event. Lifecycle events (and
  /// high-speed configs where non-lifecycle delays round to 0ms) yield
  /// via `Task.yield()` instead of sleeping — a tight publish loop
  /// without either would starve observer polls (`scenePhase` forwards,
  /// test `waitForState` predicates, etc.).
  private func sleepOrYield(milliseconds: Int) async {
    if milliseconds > 0 {
      let deadline = ContinuousClock.now.advanced(by: .milliseconds(milliseconds))
      currentSleepDeadline = deadline
      try? await Task.sleep(until: deadline)
      currentSleepDeadline = nil
    } else {
      await Task.yield()
    }
  }

  /// Rotation / stop decision after a source finishes its plan.
  /// Separate from `runPlayback` both to keep that function's
  /// complexity within swiftlint's bounds and because the policy
  /// (loop-forever vs stop-after-last × transition-signal vs stop)
  /// reads cleaner as a single switch.
  private enum AdvanceAction {
    /// Keep playing; `nextIndex` is the source to play next.
    case `continue`(nextIndex: Int)
    /// Stop the playback task. State has already been set to its
    /// terminal value (`.idle` or `.playing(lastIndex, plan.count)`).
    case stop
  }

  private func advanceAfterSource(currentIndex: Int) -> AdvanceAction {
    let isLastSource = currentIndex == sources.count - 1
    switch config.loopBehaviour {
    case .loop:
      let nextIndex = (currentIndex + 1) % sources.count
      resetPerDemoState()
      if case .playing = state {
        state = .playing(sourceIndex: nextIndex, eventCursor: 0)
      }
      return .continue(nextIndex: nextIndex)
    case .stopAfterLast where !isLastSource:
      // Advance to next source without wrap-around. Spec §4.6:
      // `.stopAfterLast` plays each source once in order.
      let nextIndex = currentIndex + 1
      resetPerDemoState()
      if case .playing = state {
        state = .playing(sourceIndex: nextIndex, eventCursor: 0)
      }
      return .continue(nextIndex: nextIndex)
    case .stopAfterLast:
      // Last source finished — honour `onComplete`.
      switch config.onComplete {
      case .awaitTransitionSignal:
        // Hold at `.playing(lastIndex, plan.count)` until the
        // download-complete signal arrives. Default DL-demo uses
        // `.loop + .awaitTransitionSignal`; this branch is for
        // single-pass replays that still want hold-on-done.
        return .stop
      case .stopPlayback:
        // Future user-replay surface (spec §4.5). Revert to `.idle`
        // so the UI can offer a restart.
        state = .idle
        return .stop
      }
    }
  }

  private func resetPerDemoState() {
    agentOutputs = []
    currentPhase = nil
    currentRound = nil
    currentTotalRounds = nil
  }

  // MARK: - Render-time state updates

  /// Applies `event` to observable state with narrow ContentFilter
  /// scope. Mirror of the live ``SimulationViewModel/handleEvent(_:)``
  /// for the subset of events ``YAMLReplaySource/plannedEvents()``
  /// can emit — see the sync-risk note in this file's header.
  private func apply(_ event: SimulationEvent) {
    switch event {
    case .roundStarted(let round, let totalRounds):
      currentRound = round
      currentTotalRounds = totalRounds

    case .phaseStarted(let phaseType, _):
      currentPhase = phaseType

    case .agentOutput(let agent, let output, let phaseType):
      let filtered = contentFilter.filter(output)
      agentOutputs.append(
        AgentOutputEntry(agent: agent, output: filtered, phaseType: phaseType))

    case .summary, .scoreUpdate, .elimination, .voteResults,
      .pairingResult, .assignment, .eventInjected:
      // Code-phase events currently have no observable state surface
      // in PR1 — the host view's scoreboard / results strip is the
      // PR2 concern. ContentFilter is still applied in a follow-up
      // commit when those surfaces land. For now these events update
      // nothing visible; rendering them is a no-op here.
      return

    case .roundCompleted, .phaseCompleted, .simulationCompleted,
      .simulationPaused, .conditionalEvaluated, .agentOutputStream,
      .inferenceStarted, .inferenceCompleted, .error:
      // Never emitted by `YAMLReplaySource.plannedEvents()` (see the
      // sync-risk note in the header). A `.error` in particular would
      // signal primitive-level breakage; replay's own failure surface
      // goes through the state machine, not the event stream.
      return
    }
  }

  // MARK: - Pacing helpers

  /// Per-event sleep in milliseconds. Reads ``playbackSpeed`` (the
  /// runtime-mutable VM state, not `config.playbackSpeed`) so a Speed
  /// Menu change reflects on the next call.
  ///
  /// `.instant` short-circuits to 0ms before the multiplier division —
  /// symmetric with the early-return in ``YAMLReplaySource``. The
  /// `.infinity` sentinel on `.instant.multiplier` would arithmetically
  /// produce 0 too, but explicit early-return avoids depending on
  /// IEEE-754 division semantics.
  private func scaledDelay(for kind: PacedEvent.Kind) -> Int {
    if playbackSpeed == .instant { return 0 }
    let speed = max(playbackSpeed.multiplier, 0.001)
    switch kind {
    case .turn:
      return Int(Double(config.turnDelayMs) / speed)
    case .codePhase:
      return Int(Double(config.codePhaseDelayMs) / speed)
    case .lifecycle:
      return 0
    }
  }

  /// Computes the outstanding sleep in milliseconds given
  /// ``currentSleepDeadline``. Returns 0 when not currently sleeping
  /// (i.e. the VM is between events).
  private func remainingDelayMs() -> Int {
    guard let deadline = currentSleepDeadline else { return 0 }
    let remaining = deadline - ContinuousClock.now
    let (seconds, attoseconds) = remaining.components
    let milliseconds = Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    return max(0, milliseconds)
  }
}
