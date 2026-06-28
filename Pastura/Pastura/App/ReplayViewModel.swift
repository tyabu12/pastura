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
  ///
  /// **Real game-round counter** — driven by `.roundStarted` events,
  /// independent of ``currentPhaseIndex``. Most preset scenarios (e.g.
  /// Word Wolf) play a single game round but step through multiple
  /// phases, so `currentRound == 1` while `currentPhaseIndex` walks
  /// 1..N. The chat-stream's `roundSeparator` reads this; the GameHeader
  /// row 2 displays ``currentPhaseIndex`` (the pseudo-ROUND for Demo).
  private(set) var currentRound: Int?

  /// Most-recent `.roundStarted.totalRounds`. See ``currentRound``.
  private(set) var currentTotalRounds: Int?

  /// Tracks `.phaseStarted` event count consumed within the
  /// currently-playing source. Backs ``currentPhaseIndex``.
  /// Lives on the underlying state (not gated by `state`) so the
  /// counter survives pause/resume; the public computed property
  /// hides it during non-playing states.
  private var phaseProgress: Int = 0

  /// Cached total `.phaseStarted` event count for the currently-
  /// playing source. Set in ``resetPerDemoState(forSourceIndex:)``;
  /// re-derived on `.loop` rotation against the new source. Backs
  /// ``totalPhaseCount``.
  private var cachedTotalPhaseCount: Int = 0

  /// User-selectable playback speed. Initialized from
  /// ``ReplayPlaybackConfig/playbackSpeed`` and writable at runtime
  /// (Demo controlBar's Speed Menu assigns to it directly, mirroring
  /// ``SimulationViewModel/speed``).
  ///
  /// **Plain `var` (intentionally not `private(set)`) for Sim parity.**
  /// Every other observable property on this VM is `private(set) var`
  /// (`state`, `currentPhase`, `currentRound`, …) and routes mutation
  /// through explicit transition methods. `playbackSpeed` instead
  /// matches ``SimulationViewModel/speed`` — the UI assigns directly
  /// (`viewModel.playbackSpeed = .fast`) over `PlaybackSpeed.allCases`.
  /// All four cases are valid; no validation guard is required, so a
  /// dedicated `setPlaybackSpeed(_:)` would only add API surface.
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

  /// Whether agent thought lines (`▸ THINKING`) are expanded across the
  /// demo chat stream. Owned here (not on the host `View`) so the pacing
  /// floor can read it — the turn-dwell estimate only counts the thought
  /// segment's typing time when thoughts are shown. Default `true` mirrors
  /// the Sim / Results state. Aligns the demo with Sim's per-VM toggle
  /// (``SimulationViewModel``); ``ModelDownloadHostView`` binds the control
  /// bar's ``ThoughtVisibilityToggle`` to `$viewModel.showAllThoughts`.
  var showAllThoughts: Bool = true

  /// Chat-stream timeline backing the host view's `ScrollView` —
  /// mixed agent outputs and demo-boundary markers in publish order.
  ///
  /// Accumulates **across demo rotation** (#208): when a demo ends and
  /// the VM advances to the next source, the previous bubbles stay in
  /// `chatItems` and a ``ChatItem/demoBoundary`` separator is appended
  /// before the next source's events start arriving. The host view's
  /// existing `scrollTo(lastId, anchor: .bottom)` then naturally scrolls
  /// the older content up.
  ///
  /// **Reset rules**:
  /// - ``start()`` clears `chatItems` (fresh-start invariant — survives
  ///   re-`start()` after `.stopPlayback`-driven terminal `.idle`).
  /// - On `.loop` wrap-around (last source → source 0), `chatItems` is
  ///   wiped without a boundary marker; the full visual reset is itself
  ///   the "new cycle" signal (see UI spec §"Demo boundary marker").
  /// - On mid-cycle rotation (any non-wrap rotation), `chatItems` keeps
  ///   accumulating; a ``ChatItem/demoBoundary`` carrying
  ///   `sources[nextIndex].scenario.name` is appended before the next
  ///   source publishes.
  /// - On `.stopAfterLast` terminal (both `.awaitTransitionSignal` and
  ///   `.stopPlayback`), `chatItems` is left untouched — the last source's
  ///   bubbles remain on screen through the hold/idle state.
  private(set) var chatItems: [ChatItem] = []

  /// Derived projection over ``chatItems`` exposing only agent outputs.
  /// Boundary markers are filtered out.
  ///
  /// Retained as a compatibility shim so existing test sites
  /// (`ReplayViewModelTests+ContentFilter`, `+UserPause`, `+Speed`,
  /// `DemoReplayIntegrationTests`) reading `agentOutputs.count >= 1`
  /// patterns continue to work; **new code should read ``chatItems``
  /// directly** to render the boundary markers between demos.
  ///
  /// SwiftUI observation works correctly because @Observable instruments
  /// reads on the underlying stored ``chatItems``; consumers reading
  /// `agentOutputs` reach `chatItems` through the computed body and the
  /// registrar tracks the dependency.
  var agentOutputs: [AgentOutputEntry] {
    chatItems.compactMap {
      if case .agentOutput(let entry) = $0 { return entry }
      return nil
    }
  }

  /// Character-reveal rate fed to each ``AgentOutputRow`` by
  /// ``ModelDownloadHostView``. ``ReplayPlaybackConfig/typingCharsPerSecond``
  /// is the **opt-in gate** (`nil` ⇒ instant text / no proportional dwell —
  /// non-demo configs; non-nil ⇒ demo); when opted in, the *value* tracks the
  /// runtime ``playbackSpeed`` so the demo's Speed menu drives typing the way
  /// Sim does (`x0.5`→15 / `x1`→30 / `x1.5`→45 / `Max`→nil instant). Before
  /// #791 this returned the fixed `config.typingCharsPerSecond` and ignored
  /// the Speed menu, so the menu only changed turn dwell, not typing.
  ///
  /// `playbackSpeed` is a plain stored property on this `@Observable` VM, so
  /// SwiftUI re-renders the host (and rebuilds the row with the new cps) when
  /// the menu mutates it — no manual `@Observable` bridge needed.
  ///
  /// The turn-dwell floor (``typingFloorMs(for:script:)``) reads this **same**
  /// speed-scaled value, so the floor is real wall-clock time at the current cps
  /// rather than a fixed reference divided later. Typing animation, dwell floor,
  /// and the live Sim (``SimulationViewModel/effectiveCharsPerSecond(forEntryId:)``)
  /// all resolve from the one ``PlaybackSpeed/charsPerSecond`` source of truth,
  /// so they cannot drift.
  var typingCharsPerSecond: Double? {
    // `config.typingCharsPerSecond` gates demo (non-nil) vs non-demo (nil).
    guard config.typingCharsPerSecond != nil else { return nil }
    return playbackSpeed.charsPerSecond
  }

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

  /// Heterogeneous chat-stream item — either an agent's rendered output
  /// or a demo-boundary marker inserted between sources during rotation
  /// (#208). Used by the host view's `ForEach` to dispatch on case.
  ///
  /// `id` is projected from the inner payload so SwiftUI's
  /// `ForEach`/`scrollTo(_:anchor:)` keep working identically to the
  /// pre-#208 `AgentOutputEntry`-only timeline.
  nonisolated enum ChatItem: Sendable, Equatable, Identifiable {
    case agentOutput(AgentOutputEntry)
    case demoBoundary(id: UUID, scenarioName: String)

    var id: UUID {
      switch self {
      case .agentOutput(let entry): return entry.id
      case .demoBoundary(let id, _): return id
      }
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

  // MARK: - Public computed properties (GameHeader integration)

  /// Currently-active source index — "which demo is on screen right
  /// now." Returns the `sourceIndex` for BOTH `.playing` and `.paused`;
  /// `nil` for `.idle` and `.transitioning` where no source is active.
  ///
  /// **Canonical identity gate for the GameHeader surface.** The four
  /// computed properties below (``currentPhaseIndex``,
  /// ``totalPhaseCount``, ``headerRound``, and the identity reads on
  /// the host view side — `currentPresetName` and `agentPosition`) all
  /// gate on this, so the GameHeader's scenario name, ROUND fragment,
  /// and sheep-avatar colors stay stable across pause / resume. The
  /// `status` pill (.paused vs .demoing) is the user signal for
  /// pause; the other fragments preserve position context.
  ///
  /// **History**: #297 PR3 originally had ROUND collapse on pause
  /// (`.playing`-only gate); #355 found avatar colors and scenario
  /// name flickered for the same reason; the follow-up unified all
  /// identity reads onto this gate (#355 PR body).
  ///
  /// **Prefer this over external `if case .playing(let i, _) = state`
  /// pattern-matching** when only source identity is needed —
  /// `.paused(sourceIndex: i, ...)` carries the same identity.
  var currentSourceIndex: Int? {
    switch state {
    case .playing(let sourceIndex, _),
      .paused(let sourceIndex, _, _, _):
      return sourceIndex
    case .idle, .transitioning:
      return nil
    }
  }

  /// 1-based phase index within the active source. Increments on each
  /// consumed `.phaseStarted`. `nil` while no source is active
  /// (`.idle` / `.transitioning`) so the GameHeader's ROUND fragment
  /// collapses uniformly with the rest of the identity surface; stays
  /// visible across `.paused` so the user keeps position context
  /// (re-evaluation of #297 PR3 spec — see ``currentSourceIndex``).
  ///
  /// Distinct from ``currentRound`` (real game-rounds from
  /// `.roundStarted` events). Demo's GameHeader displays this
  /// pseudo-ROUND because most preset scenarios play one game-round
  /// across multiple phases, leaving the real round counter stuck
  /// at `1/1` for the entire demo.
  var currentPhaseIndex: Int? {
    guard currentSourceIndex != nil else { return nil }
    return phaseProgress > 0 ? phaseProgress : nil
  }

  /// Total `.phaseStarted` event count for the active source.
  /// Re-derived on `.loop` rotation against the new source's
  /// `plannedEvents()`. `nil` while no source is active so the
  /// GameHeader's ROUND fragment collapses uniformly with
  /// ``currentPhaseIndex``; stays visible across `.paused`.
  var totalPhaseCount: Int? {
    guard currentSourceIndex != nil else { return nil }
    return cachedTotalPhaseCount > 0 ? cachedTotalPhaseCount : nil
  }

  /// Round-counter pair for `GameHeader`'s row-2 ROUND fragment.
  /// Re-uses ``currentPhaseIndex`` and ``totalPhaseCount`` so the
  /// pair-or-nothing semantic is satisfied automatically: both gate on
  /// ``currentSourceIndex`` (non-nil for `.playing` + `.paused`) AND a
  /// positive backing value, so the wrapper collapses to `nil`
  /// whenever either piece is missing — including the brief
  /// post-`start()` window where `cachedTotalPhaseCount` has
  /// pre-computed but `phaseProgress` is still `0` (no `.phaseStarted`
  /// consumed yet).
  ///
  /// Demo's call site passes `viewModel.headerRound` directly into
  /// `GameHeader.init` instead of the pre-#313 two-Optional-Int form.
  var headerRound: GameHeaderRound? {
    guard let current = currentPhaseIndex, let total = totalPhaseCount
    else { return nil }
    return GameHeaderRound(current: current, total: total)
  }

  /// `GameHeaderStatus` for the trailing pill. `.demoing` while
  /// playing or in the brief `.transitioning` fade; `.paused` while
  /// paused (any reason). `.idle` defaults to `.demoing` —
  /// effectively unreachable in production (host view doesn't show
  /// the header pre-`start()`), but the fall-through is defensive.
  var status: GameHeaderStatus {
    switch state {
    case .idle, .transitioning, .playing:
      return .demoing
    case .paused:
      return .paused
    }
  }

  // MARK: - Transition methods

  /// Begins playback from the first source, first event.
  ///
  /// No-op if already playing or transitioning. Resets observable
  /// state so a second `.idle → .playing` cycle gets a clean slate —
  /// including ``chatItems``, which is the only piece of accumulator
  /// state that survives across rotation. Required for re-`start()`
  /// after `.stopPlayback` terminal `.idle`, where leftover items from
  /// the prior session would otherwise leak into the new run.
  func start() {
    guard case .idle = state else { return }
    guard !sources.isEmpty else { return }
    let startIndex = 0
    chatItems = []
    resetPerDemoState(forSourceIndex: startIndex)
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
    // CASE-EXHAUSTIVE on `PauseReason`: each new reason added to
    // ``PauseReason`` must make an explicit choice here between
    // "user-pause overrides this reason" (current behavior for
    // `.scenePhase`) vs. "user-pause is no-op against this reason."
    // The current intuition is "newer pause reasons are less sticky
    // than .user", but the compiler will force the decision when a
    // third case lands.
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
    // Reading-density class for this source's dwell floor — constant for the
    // whole source (language can't change mid-stream), resolved once like the
    // Sim's per-run `script`.
    let script = ReadingScript.resolve(
      engineLanguage: sources[sourceIndex].scenario.engineLanguage)
    var cursor = startCursor
    var overrideMs = firstSleepOverrideMs
    // Typing-dwell floor owed by the previously-applied agent bubble (raw,
    // pre-speed). A LOCAL var — seeded 0 on each `playSource` entry — so it
    // never leaks across a source rotation (`advanceAfterSource` re-enters
    // with a fresh call) or a resume-from-background restart (which supplies
    // `firstSleepOverrideMs`). The resume override bypasses the floor for the
    // single restarted event, which is correct: its remaining sleep was
    // already computed with the floor folded in before backgrounding.
    var pendingFloorMs = 0
    while cursor < plan.count {
      if Task.isCancelled { return }
      let paced = plan[cursor]
      let delayMs = overrideMs ?? scaledDelay(for: paced.kind, floorMs: pendingFloorMs)
      overrideMs = nil
      await sleepOrYield(milliseconds: delayMs)
      if Task.isCancelled { return }
      apply(paced.event)
      // The floor for THIS bubble gates the delay before the NEXT event — the
      // window during which this bubble is typing on screen.
      pendingFloorMs = typingFloorMs(for: paced.event, script: script)
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
    // Out of scope for proportional turn dwell (#779): the source's LAST
    // bubble gets no dwell floor here — the floor only widens the delay that
    // sits *before* the next event, and rotation/wrap has no such next-event
    // sleep to widen. So a long final bubble of a source may still be mid-type
    // when the rotation fires. Accepted; covering it would need a post-event
    // settle hop the playback loop doesn't currently have.
    let isLastSource = currentIndex == sources.count - 1
    switch config.loopBehaviour {
    case .loop:
      let nextIndex = (currentIndex + 1) % sources.count
      // Branch (a) wrap vs (b) mid-cycle (#208). Wrap = full cycle of
      // `sources` complete; the visual reset itself signals the new
      // cycle, so no boundary marker. Mid-cycle keeps accumulating with
      // a marker carrying the next source's scenario name.
      if nextIndex == 0 {
        chatItems = []
      } else {
        chatItems.append(
          .demoBoundary(
            id: UUID(),
            scenarioName: sources[nextIndex].scenario.name))
      }
      resetPerDemoState(forSourceIndex: nextIndex)
      if case .playing = state {
        state = .playing(sourceIndex: nextIndex, eventCursor: 0)
      }
      return .continue(nextIndex: nextIndex)
    case .stopAfterLast where !isLastSource:
      // Branch (c). Advance to next source without wrap-around. Spec
      // §4.6: `.stopAfterLast` plays each source once in order.
      // Sequential rotation always accumulates with a boundary marker —
      // there is no wrap variant under `.stopAfterLast`.
      let nextIndex = currentIndex + 1
      chatItems.append(
        .demoBoundary(
          id: UUID(),
          scenarioName: sources[nextIndex].scenario.name))
      resetPerDemoState(forSourceIndex: nextIndex)
      if case .playing = state {
        state = .playing(sourceIndex: nextIndex, eventCursor: 0)
      }
      return .continue(nextIndex: nextIndex)
    case .stopAfterLast:
      // Branch (d). Last source finished — honour `onComplete`.
      // No `chatItems` mutation in either terminal branch: the last
      // source's bubbles stay on screen through the hold / idle state.
      switch config.onComplete {
      case .awaitTransitionSignal:
        // Hold at `.playing(lastIndex, plan.count)` until the
        // download-complete signal arrives. Default DL-demo uses
        // `.loop + .awaitTransitionSignal`; this branch is for
        // single-pass replays that still want hold-on-done.
        return .stop
      case .stopPlayback:
        // Future user-replay surface (spec §4.5). Revert to `.idle`
        // so the UI can offer a restart. `chatItems` survives until the
        // next `start()` clears it (see `start()` doc-comment).
        state = .idle
        return .stop
      }
    }
  }

  /// Per-source state reset. Called from `start()` (initial source)
  /// and `advanceAfterSource()` (loop / sequential rotation). The
  /// `forSourceIndex` parameter is load-bearing for the
  /// ``cachedTotalPhaseCount`` re-derivation against the new source's
  /// `plannedEvents()`.
  ///
  /// **Does not touch ``chatItems``** (#208): caller decides — `start()`
  /// clears unconditionally, `advanceAfterSource` decides per the
  /// rotation branch (wrap → wipe, mid-cycle → append boundary +
  /// accumulate, terminal → no-op).
  private func resetPerDemoState(forSourceIndex sourceIndex: Int) {
    currentPhase = nil
    currentRound = nil
    currentTotalRounds = nil
    phaseProgress = 0
    cachedTotalPhaseCount = Self.countPhases(in: sources[sourceIndex])
  }

  /// Pre-computes the number of `.phaseStarted` events in a source's
  /// planned event list. Done once per source-entry rather than on
  /// every observation read so a Demo running for minutes doesn't
  /// repeatedly walk the plan array each SwiftUI render pass.
  private static func countPhases(in source: any ReplaySource) -> Int {
    source.plannedEvents().filter { paced in
      if case .phaseStarted = paced.event { return true }
      return false
    }.count
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
      // Increment pseudo-ROUND counter. Survives pause/resume; reset
      // only on source rotation via ``resetPerDemoState(forSourceIndex:)``.
      phaseProgress += 1

    case .agentOutput(let agent, let output, let phaseType):
      let filtered = contentFilter.filter(output)
      chatItems.append(
        .agentOutput(
          AgentOutputEntry(agent: agent, output: filtered, phaseType: phaseType)))

    case .summary, .scoreUpdate, .elimination, .voteResults,
      .pairingResult, .assignment, .eventInjected:
      // Code-phase events currently have no observable state surface
      // in PR1 — the host view's scoreboard / results strip is the
      // PR2 concern. ContentFilter is still applied in a follow-up
      // commit when those surfaces land. For now these events update
      // nothing visible; rendering them is a no-op here.
      return

    case .roundCompleted, .phaseCompleted, .simulationCompleted,
      .roundCheckpoint, .simulationPaused, .conditionalEvaluated,
      .agentOutputStream, .inferenceStarted, .inferenceCompleted, .error,
      .languageMismatch:
      // Never emitted by `YAMLReplaySource.plannedEvents()` (see the
      // sync-risk note in the header). A `.error` in particular would
      // signal primitive-level breakage; replay's own failure surface
      // goes through the state machine, not the event stream.
      // `.languageMismatch` arises only from live LLM inference (ADR-010
      // Step E PR2) — pre-recorded YAML replays cannot regenerate
      // adherence verdicts after the fact.
      return
    }
  }

  // MARK: - Pacing helpers

  /// Proportional turn-dwell floor (raw ms, **real wall-clock at the current
  /// speed**) the *next* inter-event delay must cover so the just-applied agent
  /// bubble finishes its ``AgentOutputRow`` reveal — and is read for a beat —
  /// before the next turn appears.
  ///
  /// The floor is `typingMs + readingDwellMs` — the bubble types its whole line
  /// over `typingMs`, then the reading dwell is an absorb beat held AFTER the
  /// line is fully shown. This differs from the live Sim's
  /// ``SimulationViewModel/holdAfterAgentOutput(script:)``, which uses
  /// `max(dwell, remaining-tail-typing)`: there the line was already revealed
  /// during live streaming *before* the hold begins, so the hold only needs the
  /// dwell (the tail term is tiny). The demo has no streaming pre-reveal — the
  /// entire reveal happens inside this floor window — so the dwell must be added
  /// on top of the typing, not max-ed against it (a max would erase the reading
  /// pause on any line whose typing already exceeds the dwell). Both terms are
  /// computed at the *actual* speed-scaled cps / tier (the same
  /// ``typingCharsPerSecond`` the row animates at), so the floor is already real
  /// time and ``scaledDelay(for:floorMs:)`` must NOT divide it again by the
  /// speed multiplier.
  ///
  /// Returns 0 for non-agent events (nothing is typing) and when there is no
  /// proportional dwell — the config opts out
  /// (``ReplayPlaybackConfig/typingCharsPerSecond`` `== nil`, non-demo) or
  /// playback is `.instant`; both surface as a nil ``typingCharsPerSecond``.
  ///
  /// `script` is the current source's reading-density class (from
  /// ``Scenario/engineLanguage``), resolved once per ``playSource(sourceIndex:startCursor:firstSleepOverrideMs:)``
  /// entry and threaded in — constant within a source, exactly as the Sim passes
  /// it to `holdAfterAgentOutput`. The reading dwell's `displayLength` is the
  /// **primary** grapheme count only (thought excluded), matching the Sim's
  /// `lastAgentOutputDisplayLength`; the thought, when shown, still counts toward
  /// the typing term via ``TurnOutput/revealedSegments(for:includeThought:)``.
  ///
  /// The thought segment is gated on the global ``showAllThoughts``. NOTE:
  /// ``AgentOutputRow`` honours a *per-row* `showInnerThought` seeded from
  /// this global but then mutable via the row's chevron, so a mid-flight
  /// chevron tap on the latest row makes this estimate slightly inexact. That
  /// is an accepted heuristic imprecision — the floor is a lower bound on
  /// dwell, not a frame-exact contract (animation timing is code-review-gated
  /// per `.claude/rules/view-testing.md` rule 4, not asserted). `internal`
  /// (not `private`) so `ReplayViewModelTests+Pacing` can exercise it.
  func typingFloorMs(for event: SimulationEvent, script: ReadingScript) -> Int {
    guard case .agentOutput(_, let output, let phaseType) = event else { return 0 }
    // Use the *actual* speed-scaled cps (the same value `AgentOutputRow`
    // animates at) so the floor is real wall-clock time at the current speed —
    // NOT a fixed reference divided later. A nil value covers both the opt-out
    // config (non-demo) and `.instant` (no typing, no dwell).
    guard let cps = typingCharsPerSecond else { return 0 }
    let segments = output.revealedSegments(
      for: phaseType, includeThought: showAllThoughts)
    let typing = typingDurationMs(
      primary: segments.primary, thought: segments.thought, charsPerSecond: cps)
    // No text to type ⇒ no hold (an empty bubble shouldn't gate the next turn).
    guard typing > 0 else { return 0 }
    let dwellMs = Self.milliseconds(
      playbackSpeed.readingDwell(
        displayLength: segments.primary.count, script: script))
    return typing + dwellMs
  }

  /// Whole milliseconds of a `Duration` that carries only ms precision
  /// (``PlaybackSpeed/readingDwell(displayLength:script:)`` builds it via
  /// `.milliseconds`), so the round-trip back to `Int` ms is lossless.
  private static func milliseconds(_ duration: Duration) -> Int {
    let (seconds, attoseconds) = duration.components
    return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
  }

  /// Per-event sleep in milliseconds. Reads ``playbackSpeed`` (the
  /// runtime-mutable VM state, not `config.playbackSpeed`) so a Speed
  /// Menu change reflects on the next call.
  ///
  /// `.instant` short-circuits to 0ms — symmetric with the early-return in
  /// ``YAMLReplaySource``. The `.infinity` sentinel on `.instant.multiplier`
  /// would arithmetically produce 0 too, but explicit early-return avoids
  /// depending on IEEE-754 division semantics.
  ///
  /// The **structural base** (``ReplayPlaybackConfig/turnDelayMs`` /
  /// `codePhaseDelayMs`) scales with ``PlaybackSpeed/multiplier``. `floorMs` —
  /// the proportional turn-dwell floor from ``typingFloorMs(for:script:)`` — is
  /// already real wall-clock time at the current cps, so it is **NOT** divided;
  /// the result is `max(base / multiplier, floorMs)`. This mirrors the live Sim,
  /// whose hold (`max(readingDwell, pendingTypingHold)`) scales neither term by
  /// a multiplier. A long bubble therefore holds the next turn until it has
  /// typed out + been read, while short turns keep the flat ``turnDelayMs``
  /// rhythm. `.instant` ignores the floor too (collapses to 0). `internal`
  /// (not `private`) so `ReplayViewModelTests+Pacing` can pin the arithmetic.
  func scaledDelay(for kind: PacedEvent.Kind, floorMs: Int = 0) -> Int {
    if playbackSpeed == .instant { return 0 }
    let speed = max(playbackSpeed.multiplier, 0.001)
    let base: Int
    switch kind {
    case .turn:
      base = config.turnDelayMs
    case .codePhase:
      base = config.codePhaseDelayMs
    case .lifecycle:
      base = 0
    }
    return max(Int(Double(base) / speed), floorMs)
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
