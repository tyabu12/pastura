// swiftlint:disable file_length
// Deliberately long: this view orchestrates the entire live simulation
// surface — header, log + typing + thinking indicators, scroll handling,
// control bar, scoreboard sheet, export flow, and lifecycle hooks. Log-
// entry rendering is already split into SimulationView+LogEntries.swift;
// further extraction would scatter state bindings across files.
import SwiftUI
import UIKit
import os

/// Live simulation execution screen with real-time log, controls, and scoreboard.
struct SimulationView: View {  // swiftlint:disable:this type_body_length
  /// How this view obtains its run: a fresh simulation for a `scenarioId`, or a
  /// resume of an already-paused run identified by its `runId`. Modelled as a
  /// single enum (not two optionals) so the two mutually-exclusive entries
  /// can't both be set; `.task` dispatches on it (ADR-016 P3, #667).
  enum Source: Hashable {
    case scenario(scenarioId: String)
    case resume(runId: String)
  }

  let source: Source
  /// Render-time hint for the navigation title — supplied by the caller
  /// (`ScenarioDetailView`'s Run Simulation push, or the Home resume card)
  /// so the title is correct from the first frame of the push, before the
  /// scenario YAML is (re-)parsed. `nil` falls back to the empty-string
  /// placeholder. See ADR-008.
  var initialName: String?

  @Environment(\.scenePhase) private var scenePhase
  @Environment(AppDependencies.self) private var dependencies
  // Router (current tab's, via the tab-scoped injection) drives the back-button
  // confirm-on-leave flow (#673): the back button pops through `router`. Focus
  // mode (ADR-017) hides the tab bar during a run, so a mid-run tab switch — and
  // the TabCoordinator defer path it used to need — is impossible; only the back
  // path remains.
  @Environment(AppRouter.self) private var router
  // Read to record the host tab on the app-level session at run-start, so the
  // Phase B in-flight indicator can re-select it and re-push the sim route when
  // returning to a parked-away run (ADR-017). Focus mode pins the run to whatever
  // tab is selected at start, so `selectedTab` here *is* the host tab.
  @Environment(TabCoordinator.self) private var tabCoordinator
  @State private var viewModel: SimulationViewModel?
  /// `true` while the back-button confirm-on-leave dialog is showing (#673).
  @State private var pendingBackLeave = false
  /// Set by an explicit leave (`confirmLeave` / `confirmLeaveKeepRunning`) so the
  /// trailing `onDisappear` from that path's own `router.pop()` does not
  /// re-handle the run (critic Axis 6 — would otherwise double-terminate a kept
  /// or paused run). Consumed + reset in `onDisappear`. Phase B (ADR-017).
  @State private var leaveHandled = false
  /// `true` when a *different* run already owns the session (a second-run
  /// attempt) — the view shows a "return to the running simulation" state
  /// instead of starting a competing run (Phase B, ADR-017 #682).
  @State private var alreadyRunning = false
  // Accessed from SimulationView+Background.swift extension for the toggle subtitle.
  @State var scenario: Scenario?
  @State private var showScoreboard = false
  /// Drives the final-ranking card's animated insertion at run completion
  /// (#868). Mirrors `viewModel.isCompleted`, but flipped inside `withAnimation`
  /// so the card fades/slides in — `isCompleted` is set on the VM outside any
  /// animation transaction, so gating the card on it directly would pop it in.
  @State private var resultCardVisible = false
  @State private var loadError: String?
  @State private var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State private var exportError: String?
  @State private var isExporting = false
  /// Whether the latest agent-output row is still typing. Used to suppress
  /// "X is thinking..." indicators so they don't appear above text that's
  /// still being revealed.
  @State private var latestRowIsAnimating = false

  private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "SimulationView")

  var body: some View {
    ZStack {
      baseLayer
      if let label = displayState.scrimLabel {
        // LOAD-BEARING: a SINGLE persistent scrim. This `if let` stays true
        // across awaitingScenario→loadingModel, so SwiftUI keeps the SAME
        // scrim view (and its spinner) alive instead of tearing one down and
        // building another — that continuity is the whole point of #825. Do
        // NOT split this back into per-phase overlays or add an `.id` here.
        loadingScrim(label)
          .transition(.opacity)
      }
    }
    // Animate the scrim's appear/disappear, keyed on its PRESENCE (a Bool) —
    // not the label, not the full state. Consequences (#825, critic Axis 2):
    //   • awaitingScenario→loadingModel: presence stays true → NO transaction,
    //     so the label swaps instantly and the baseLayer content swap
    //     underneath (empty→simulationContent) is NOT cross-faded. ← the case
    //     that matters; this is what keeps the handoff clean.
    //   • loadingModel→running and running↔reloadingModel: baseLayer is
    //     unchanged (simulationContent), so only the scrim fades — the live
    //     log is never cross-faded.
    //   • awaitingScenario→error/alreadyRunning (rare): presence flips AND the
    //     baseLayer swaps, so that view fades in instead of swapping instantly.
    //     Accepted — a terminal-state fade reads fine (arguably better).
    .animation(.default, value: displayState.scrimLabel != nil)
    // "Fill the bar" pattern (#312, ADR-008 §Amendment 2026-05-10).
    // The system nav bar stays in the layout (preserving swipe-back
    // gesture and the chevron + back-button label that reads the
    // upstream `ScenarioDetail`'s title), but its background is
    // hidden so the GameHeader's frosted material — extended into
    // the top safe area from the meta-row inset below — fills the
    // 44pt slot continuously. Row 1 of the GameHeader (title +
    // status pill) is hosted inside the bar via `ToolbarItem`
    // (`.principal`) so the previously-empty 44pt is now reclaimed
    // by useful content. Row 2 (round + phase + tok/s) mounts via
    // `.safeAreaInset(.top)` directly below.
    //
    // bda1f70 attempted to reclaim the 44pt by hiding the bar
    // entirely (`.toolbar(.hidden, for: .navigationBar)`) and was
    // reverted in 7af22d0 because that API has a known iOS 17.x bug
    // (FB13484530) that disables the interactive pop gesture. The
    // background-only `.toolbarBackground(.hidden, ...)` used here
    // does NOT share that bug — the bar remains in the hierarchy.
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    // Replace iOS-26 Liquid Glass back chevron with Pastura's flat
    // PasturaBackButton. The custom chevron is narrower than the
    // system "< Pastura" rendering, so the principal slot's available
    // width INCREASES rather than compresses on small iPhones (Critic
    // Axis 2 width-gate verification: chevron-only ~30pt vs system
    // chevron+text ~80pt). View-level swipe-back probe per
    // PasturaBackButton's UIKit bridge documentation.
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    // Focus mode (#646): hide the bottom tab bar while a simulation is on top
    // of a tab's stack, so tab-switching mid-run is structurally impossible.
    // That removes the only foreground path that tore the view-scoped run down
    // and reset it (tab switch → onDisappear → `.task` cancel → fresh `run()`
    // on return). The only exits are back / swipe-back, where the
    // confirm-on-leave dialog + `.paused` safety net already apply. `.tabBar` is
    // a separate toolbar surface from the navigationBar hide matrix in
    // `.claude/rules/swiftui-traps.md` — it does NOT touch the back chevron or
    // the swipe-back gesture. Applied to the whole view so it covers both the
    // `.simulation` and `.resumeSimulation` routes (both render SimulationView).
    // See ADR-017; opt-in cross-screen continuation is deferred to Phase B.
    .toolbar(.hidden, for: .tabBar)
    .onAppear { viewModel?.setViewVisible(true) }
    // Viewer-prediction sheet (#915). The binding's nil-set path (interactive
    // dismiss, blocked below) routes to a skip; normal resolution is driven by
    // the sheet's `onResolve`, which clears `predictionPrompt` in the VM.
    .sheet(
      item: Binding(
        get: { viewModel?.predictionPrompt },
        set: { if $0 == nil { viewModel?.resolvePrediction(.skipped) } })
    ) { prompt in
      ViewerPredictionSheet(
        question: prompt.question,
        candidates: prompt.candidates,
        onResolve: { viewModel?.resolvePrediction($0) }
      )
      .presentationDetents([.medium, .large])
    }
    .task {
      // Phase B (ADR-017): reconnect to a run the app-level session still owns
      // instead of starting a fresh one. Under "keep running" the run survives
      // `onDisappear` (parked in memory), so a returning view re-projects the
      // live view model and un-parks the view-hide suspend — no model reload,
      // mid-generate preserved.
      let session = dependencies.simulationSession
      if let adopted = session.adoptIfMatching(source: source) {
        viewModel = adopted
        scenario = session.scenario
        // Deliberately NO reveal-state reset here: the adopted VM carries
        // `introRevealHasBegun` / `latestRowRevealCompleted` from the original
        // mount, and that survival is exactly what keeps the premise + latest
        // row from re-typing on this re-projection (#934). `beginIntro` /
        // `run()`'s reset run only on a fresh start, which this path bypasses.
        // Returning to the screen clears the view-hide park; if no other reason
        // holds (app-background / user-pause), the parked generate resumes.
        session.requestResume(reason: .viewHide)
        return
      }
      // A *different* run owns the session (a parked-away run while the user
      // tapped Run on another scenario). Refuse the second run and offer to
      // return to the live one rather than starting a competing run (the start
      // guard would refuse anyway; this surfaces it as actionable UI).
      if session.isLive {
        alreadyRunning = true
        return
      }
      switch source {
      case .scenario(let scenarioId):
        await loadAndRun(scenarioId: scenarioId)
      case .resume(let runId):
        await loadAndResume(runId: runId)
      }
    }
    // Phase B (ADR-017) PR2: park vs. end on disappear.
    //
    // `leaveHandled` short-circuits the trailing `onDisappear` that an explicit
    // leave's own `router.pop()` triggers — without it, "Leave & keep running"
    // would park then immediately `end()` the kept run, and "Pause and leave"
    // would write `.paused` twice (critic Axis 6). Only an *unhandled* disappear
    // (a true swipe-back) reaches the park-vs-end arm, keyed on the opt-in:
    // Setting on + in-flight → park (`requestPark(.viewHide)`); otherwise
    // `end()` (today's cancel-on-disappear terminal ladder → resumable
    // `.paused`). Ownership-guarded so a view that never owned the live run
    // doesn't tear one down. See `disappearAction(...)`.
    .onDisappear {
      // Leaving the screen resolves any pending prediction sheet as a skip so
      // it doesn't resurface stale on return (#915).
      viewModel?.setViewVisible(false)
      let session = dependencies.simulationSession
      switch Self.disappearAction(
        leaveHandled: leaveHandled,
        owns: session.source == source,
        keepRunningEnabled: FeatureFlags.keepRunningOnLeaveEnabled,
        isGuarded: leaveGuardActive
      ) {
      case .ignore:
        leaveHandled = false  // consume the flag set by the explicit-leave path
      case .park:
        session.requestPark(reason: .viewHide)
      case .end:
        session.end()
      }
    }
    // Memory-pressure + scene-phase handling for the *present-view* case. When a
    // run is parked-away (no view mounted), the always-mounted in-flight
    // indicator host carries the away-case observers (see
    // `InFlightSimulationIndicator`). Both surfaces route through the single
    // throttle on `SimulationSession` so escalation/reset stays consistent.
    .onChange(of: scenePhase) { _, newPhase in
      // Two-phase BG handling (ADR-003):
      // - .background: synchronous pause for safety (stops in-flight work ASAP).
      //   If the user enabled BG continuation, the BGTask activation will fire
      //   asynchronously and switch inference to CPU + resume.
      // - .active: async switch back to GPU (if we were on CPU) and complete BG task.
      guard let viewModel, viewModel.isRunning else { return }
      switch newPhase {
      case .background:
        // Update flag synchronously before dispatching the handler so any
        // concurrently-queued BG expiration callback sees the fresh value.
        viewModel.isAppBackgrounded = true
        viewModel.handleScenePhaseBackground()
      case .active:
        viewModel.isAppBackgrounded = false
        Task { await viewModel.handleScenePhaseForeground() }
      default:
        break
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didReceiveMemoryWarningNotification
      )
    ) { _ in
      // Present-view entry to the single throttle on the session (the away-case
      // entry is the in-flight indicator host). Policy in MemoryWarningThrottle.
      dependencies.simulationSession.handleMemoryWarning(isAppActive: scenePhase == .active)
    }
    .onChange(of: viewModel?.isPaused ?? false) { _, isPaused in
      // After the user resumes, treat the previous pressure as resolved so a
      // delayed warning doesn't immediately escalate to cancel (closes the
      // "user just resumed and got cancelled" trap from critic Axis 2).
      if !isPaused { dependencies.simulationSession.resetMemoryThrottle() }
    }
    // willResignActive fires earlier than scenePhase = .background, beating
    // the iOS Metal-deny window. Backstopped by handleScenePhaseBackground.
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
    ) { _ in
      viewModel?.handleWillResignActive()
    }
    .sheet(item: $exportPayload) { payload in
      ShareSheet(activityItems: [payload.text, payload.fileURL])
    }
    .alert(
      String(localized: "Export failed"),
      isPresented: Binding(
        get: { exportError != nil },
        set: { if !$0 { exportError = nil } }
      )
    ) {
      Button(String(localized: "OK"), role: .cancel) { exportError = nil }
    } message: {
      Text(exportError ?? "")
    }
    // Back-button confirm-on-leave (#673, extended for Phase B opt-in #682).
    // Raised by `handleBackTap()` only when the keep-running Setting is off
    // (with it on, leaving silently parks — no dialog). A custom `.sheet`
    // (`SimulationLeaveSheet`), not `.alert`/`.confirmationDialog`, so the
    // three actions can carry semantic design-system colors (moss primary /
    // amber caution / neutral) — `.alert` exposes no per-button color API and
    // `.confirmationDialog` mis-anchors as a popover on iOS 26 (swiftui-traps).
    // Reuses `leaveAlertBinding`: a swipe-to-dismiss (no button) routes to
    // `stay()` via the binding's setter — the correct "keep running, didn't
    // pick anything" outcome. Focus mode (ADR-017) hides the tab bar during a
    // run, so only the back / swipe-back path reaches here.
    .sheet(isPresented: leaveAlertBinding) {
      // Wrapped in a ScrollView so the content scrolls (not clips) at the
      // largest Dynamic Type sizes; bounce is suppressed when it already fits.
      ScrollView {
        SimulationLeaveSheet(
          onPauseAndLeave: confirmLeave,
          onKeepRunning: confirmLeaveKeepRunning,
          onStay: stay)
      }
      .scrollBounceBehavior(.basedOnSize)
      .presentationDetents([.height(340)])
      .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Confirm-on-leave (#673)

  /// Pure predicate: a leave (tab-switch / back) must be confirmed only when a
  /// run is genuinely in flight and not already paused or completed. A paused
  /// run is already saved (`.paused`), and a completed one has nothing to lose.
  /// Extracted `static` so the three-flag logic is unit-tested (ADR-009).
  static func shouldGuardLeave(isRunning: Bool, isPaused: Bool, isCompleted: Bool) -> Bool {
    isRunning && !isPaused && !isCompleted
  }

  /// Whether the current run should gate a leave gesture behind the dialog.
  private var leaveGuardActive: Bool {
    guard let viewModel else { return false }
    return Self.shouldGuardLeave(
      isRunning: viewModel.isRunning,
      isPaused: viewModel.isPaused,
      isCompleted: viewModel.isCompleted)
  }

  /// The three outcomes of a back-button tap, decided purely so the routing is
  /// unit-tested (ADR-009).
  enum LeaveAction: Equatable {
    /// Nothing in flight — pop immediately, no confirm.
    case popImmediately
    /// Keep-running Setting is on — park silently and pop, no dialog.
    case silentKeepRunning
    /// In flight with the Setting off — raise the three-button confirm dialog.
    case showDialog
  }

  /// Pure decision for a back-button tap. Extracted `static` for unit testing.
  static func leaveAction(isGuarded: Bool, keepRunningEnabled: Bool) -> LeaveAction {
    guard isGuarded else { return .popImmediately }
    return keepRunningEnabled ? .silentKeepRunning : .showDialog
  }

  /// What `onDisappear` should do for the run. Pure so the "exactly one terminal
  /// action per leave path" invariant (critic Axis 6) is unit-tested without
  /// driving SwiftUI: an explicit leave sets `leaveHandled` → `.ignore`; a true
  /// swipe-back falls through to park (Setting on + in-flight) or end.
  enum DisappearAction: Equatable {
    /// Already handled by an explicit-leave path (or no run owned) — do nothing.
    case ignore
    /// Keep the run alive in memory (view-hide park).
    case park
    /// Tear the run down to a resumable `.paused` (cancel-on-disappear).
    case end
  }

  static func disappearAction(
    leaveHandled: Bool, owns: Bool, keepRunningEnabled: Bool, isGuarded: Bool
  ) -> DisappearAction {
    if leaveHandled { return .ignore }
    guard owns else { return .ignore }
    return (keepRunningEnabled && isGuarded) ? .park : .end
  }

  /// Back-button tap (#673, #682). Routes through ``leaveAction(isGuarded:keepRunningEnabled:)``.
  private func handleBackTap() {
    switch Self.leaveAction(
      isGuarded: leaveGuardActive,
      keepRunningEnabled: FeatureFlags.keepRunningOnLeaveEnabled
    ) {
    case .popImmediately:
      router.pop()
    case .silentKeepRunning:
      confirmLeaveKeepRunning()
    case .showDialog:
      pendingBackLeave = true
    }
  }

  /// `isPresented` binding for the leave dialog. The setter only fires `stay()`
  /// on a programmatic dismissal that didn't go through a button (the buttons
  /// already clear `pendingBackLeave`, so the guard skips the double-handling).
  private var leaveAlertBinding: Binding<Bool> {
    Binding(
      get: { pendingBackLeave },
      set: { presented in
        if !presented, pendingBackLeave { stay() }
      })
  }

  /// "Pause and leave": persist a resumable `.paused`, then pop the current
  /// tab's stack. Sets `leaveHandled` so the trailing `onDisappear` doesn't
  /// re-terminate (writing `.paused` twice).
  private func confirmLeave() {
    leaveHandled = true
    viewModel?.pauseSimulation()
    router.pop()
    pendingBackLeave = false
  }

  /// "Leave & keep running": park the run in memory (no pause — it resumes
  /// instantly on return) and pop. Sets `leaveHandled` so the trailing
  /// `onDisappear` doesn't `end()` the just-kept run (critic Axis 6). Also the
  /// silent-park target when the keep-running Setting is on.
  private func confirmLeaveKeepRunning() {
    leaveHandled = true
    dependencies.simulationSession.requestPark(reason: .viewHide)
    router.pop()
    pendingBackLeave = false
  }

  /// "Stay": discard the pending leave and keep running.
  private func stay() {
    pendingBackLeave = false
  }

  // MARK: - Already-running state (Phase B second-run refusal, #682)

  /// Shown when a second run is attempted while a different run owns the
  /// session. Offers to return to the live run instead of starting a competing
  /// one (the single-run guard would refuse the start anyway).
  /// Single source of truth for what the body renders, derived from the
  /// view's @State / @Observable inputs. Reads `viewModel?.isLoadingModel` /
  /// `isReloadingModel` so SwiftUI re-evaluates the body (and the scrim) when
  /// those flip. See ``SimulationDisplayState`` for the precedence contract.
  private var displayState: SimulationDisplayState {
    SimulationDisplayState.resolve(
      hasContent: viewModel != nil && scenario != nil,
      isLoadingModel: viewModel?.isLoadingModel ?? false,
      isReloadingModel: viewModel?.isReloadingModel ?? false,
      isPlayingIntro: viewModel?.isPlayingIntro ?? false,
      alreadyRunning: alreadyRunning,
      loadError: loadError)
  }

  /// The content layer behind the loading scrim. The scrim (mounted in `body`)
  /// dims whatever this renders, so the awaitingScenario→content swap happens
  /// out of sight. `loadingModel` / `reloadingModel` / `running` all share the
  /// same `simulationContent` so it is never torn down across those (the BG
  /// reload keeps the live log mounted under the dim, as before).
  @ViewBuilder private var baseLayer: some View {
    switch displayState {
    case .loadingModel, .reloadingModel, .running:
      // `displayState` guarantees content here (hasContent ⇒ viewModel != nil).
      if let viewModel { simulationContent(viewModel: viewModel) }
    case .error(let message):
      ContentUnavailableView(
        String(localized: "Error"),
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    case .alreadyRunning:
      alreadyRunningView
    case .awaitingScenario:
      // Empty base — the scenario-loading scrim provides the only visual.
      Color.clear
    }
  }

  private var alreadyRunningView: some View {
    ContentUnavailableView {
      Label(String(localized: "A simulation is already running"), systemImage: "waveform")
    } description: {
      Text(String(localized: "Return to it to keep watching, or pause it before starting another."))
    } actions: {
      Button(String(localized: "Return to the running simulation")) { returnToLiveRun() }
        .buttonStyle(.borderedProminent)
    }
  }

  /// Pops this dead-end second-run view and re-surfaces the live run on its host
  /// tab (reuses the in-flight indicator's return action).
  private func returnToLiveRun() {
    let session = dependencies.simulationSession
    guard let tab = session.tab, let route = session.returnRoute else { return }
    router.pop()
    tabCoordinator.returnToRunningSimulation(tab: tab, route: route)
  }

  private func simulationContent(  // swiftlint:disable:this function_body_length
    viewModel: SimulationViewModel
  ) -> some View {
    VStack(spacing: 0) {
      // Log
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: ChatBubbleLayout.bubbleSpacing) {
            // Opening card: the scenario premise, shown once above the first
            // agent turn so a run no longer drops straight into ASSIGN / the
            // first utterance (issue #853). Rendered as a fixed leading element
            // — NOT injected into `logEntries` — so it never persists and never
            // dims under the current-utterance opacity focus applied in the
            // ForEach below. Title is `nil`: the header already shows the name.
            // Hidden when the scenario has no description (Model init? → nil).
            // The premise types in at the playback speed as the scene-setting
            // beat; `viewModel.introRevealHasBegun` latches it to a single
            // reveal so scrolling back to the top doesn't re-type (the card
            // lives in this LazyVStack). The latch lives on the VM (not View
            // `@State`) so it survives an ADR-017 Phase B adopt re-projection —
            // returning to a parked run must not re-type the premise (#934).
            // `.instant` speed (`charsPerSecond == nil`) and Reduce Motion fall
            // to the static path inside the card. Resume entries render
            // statically (no typing, no gate) — the reveal beat is only for a
            // fresh run's start. `onRevealComplete` releases the VM intro gate
            // so the conversation starts after the reveal (#853).
            if let introModel {
              ScenarioIntroCard(
                model: introModel,
                charsPerSecond: Self.premiseCharsPerSecond(
                  isResumeEntry: isResumeEntry,
                  introRevealHasBegun: viewModel.introRevealHasBegun,
                  speedCharsPerSecond: viewModel.speed.charsPerSecond),
                leadIn: introLeadIn(for: viewModel.speed),
                onRevealStarted: { viewModel.markIntroRevealBegan() },
                onRevealComplete: { viewModel.introRevealDidComplete() }
              )
            }

            ForEach(viewModel.logEntries) { entry in
              logEntryView(entry, viewModel: viewModel, proxy: proxy)
                // Current-utterance focus: dim past rows during playback so the
                // eye settles on the line being revealed. Full opacity once the
                // run ends. The latest .agentOutput stays current; see VM.
                .opacity(viewModel.opacity(forEntryId: entry.id))
                .id(entry.id)
            }

            // Live streaming row for the in-flight inference (if any).
            // Appears once the partial parser has confirmed the primary
            // key's opening quote; before that, the "thinking" indicator
            // below stays visible. Rendered ABOVE the thinking indicators
            // so users never see "X is thinking..." and live tokens for
            // X at the same time.
            //
            // Current-utterance focus: this row is the in-flight current line,
            // so it is intentionally NOT dimmed — it lives outside the
            // logEntries ForEach (which applies `opacity(forEntryId:)`), so it
            // stays full opacity without an explicit modifier.
            if let snapshot = viewModel.streamingSnapshot {
              AgentOutputRow(
                agent: snapshot.agent,
                output: TurnOutput(fields: [:]),
                phaseType: snapshot.phaseType,
                showAllThoughts: viewModel.showAllThoughts,
                isLatest: false,
                charsPerSecond: viewModel.speed.charsPerSecond,
                // Follow the per-tick vertical growth: the snapshot-change
                // scroll below is per-token (too coarse for per-character
                // growth, and silent once the buffer is complete but the
                // reveal is still catching up at charsPerSecond).
                onRevealProgress: { scrollToBottom(proxy) },
                // Report the reveal position so the committed row can pick up
                // where the stream left off (reveal-position handoff, bug 2).
                onStreamingRevealProgress: { viewModel.reportStreamingReveal($0) },
                streamingPrimary: snapshot.primary,
                streamingThought: snapshot.thought,
                // Grow the bubble with the typed prefix, not the streaming
                // buffer: the reveal types at charsPerSecond (slower than
                // tokens arrive), so reserving the hidden tail to the buffer
                // made the box expand ahead of the visible text.
                growsWithReveal: true,
                agentPosition: scenario?.personas.firstIndex(where: { $0.name == snapshot.agent }),
                debugRowID: "stream-\(snapshot.agent)"
              )
              .id("streaming-\(snapshot.agent)")
            }

            // Thinking indicators — suppressed while the latest row is still
            // typing, so "X is thinking..." doesn't jump ahead of text the
            // user is still reading.
            if !latestRowIsAnimating {
              ForEach(Array(viewModel.thinkingAgents), id: \.self) { agent in
                HStack(spacing: 8) {
                  IdleFriendlyProgressView()
                    .scaleEffect(0.7)
                  Text(String(format: String(localized: "%@ is thinking..."), agent))
                    .textStyle(Typography.thinkingBody)
                    .foregroundStyle(Color.muted)
                }
              }
            }

            // Closing card: the settled outcome (final ranking / survival /
            // scores), shown once at completion so the result reads as the
            // terminal payoff instead of another 9pt-mono log row (#868).
            // Mirror of the opening card — a fixed trailing element, NOT a
            // logEntry, so it never dims under the current-utterance focus.
            // `resultCardVisible` is the timing gate (animated at completion);
            // `resultModel != nil` is the content gate (nil = summary-only run,
            // no card). Tap opens the full scoreboard only when real scores
            // exist — a vote-only outcome shows everything inline and a
            // scoreboard would render misleading "0 pts" rows.
            if resultCardVisible, let resultModel = resultModel(viewModel: viewModel) {
              SimulationResultCard(
                model: resultModel,
                onTap: hasRankableScores(viewModel: viewModel)
                  ? { showScoreboard = true } : nil
              )
              .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Viewer-prediction reward (#915): hit/miss + streak, shown with the
            // result card when the run had an answered prediction.
            predictionOutcomeBadge(viewModel: viewModel)

            // Bottom sentinel: scrollTo target that stays below every other
            // section (log entries, thinking indicators). Scrolling here
            // reliably reveals whatever just appeared last — anchoring to
            // the last LogEntry wouldn't follow a newly-shown thinking row.
            Color.clear
              .frame(height: 1)
              .id(Self.bottomSentinelID)
          }
          // Container-level horizontal padding (20pt, matching Demo
          // strategy) replaces the per-row `.padding(.horizontal)` on
          // each log entry / thinking indicator / streaming row. See
          // #273 PR 2 — chat-stream token alignment across Demo / Sim
          // / Results.
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
        }
        .onChange(of: viewModel.logEntries.count) { _, _ in
          scrollToBottom(proxy)
        }
        .onChange(of: viewModel.isCompleted) { _, done in
          // The no-drift completion path appends no logEntry (the count-driven
          // scroll above never fires), so drive the closing card's animated
          // reveal + a scroll here (#868).
          withAnimation(.easeOut(duration: 0.35)) { resultCardVisible = done }
          if done { scrollToBottom(proxy) }
        }
        .onAppear {
          // Mounting onto an already-completed run (no isCompleted transition
          // to observe) — show the card without the entrance animation.
          if viewModel.isCompleted { resultCardVisible = true }
        }
        .onChange(of: viewModel.thinkingAgents) { _, _ in
          // New or cleared thinking agent — when the sentinel is currently
          // rendered (i.e., typing is done), follow it.
          if !latestRowIsAnimating { scrollToBottom(proxy) }
        }
        .onChange(of: latestRowIsAnimating) { _, nowAnimating in
          // Typing just finished: the thinking indicator (if any) became
          // visible; bring it into view.
          if !nowAnimating { scrollToBottom(proxy) }
        }
        // Live streaming row lifecycle + growth.
        //
        // Unlike the pseudo-typing path (where the concat trick
        // `Text(visible) + Text(hidden).clear` pre-establishes the final
        // layout, so the row height stays fixed as chars fill in), the
        // streaming row's `streamingPrimary` itself grows per token, so
        // the row height grows too — without following it, long outputs
        // disappear past the bottom of the viewport.
        //
        // Branches:
        // - Agent transition (`nil → X`, `X → nil`, or `X → Y`): animated
        //   scroll to mark the "new speaker" / commit moment.
        // - Content growth within the same agent: raw `scrollTo` without
        //   `withAnimation`. The default 0.35s implicit animation would
        //   compound across token arrivals (~20/s) into visible stutter.
        //   `bottomSentinelID` is idempotent when already pinned to bottom.
        .onChange(of: viewModel.streamingSnapshot) { old, new in
          if old?.agent != new?.agent {
            scrollToBottom(proxy)
          } else if new != nil {
            proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
          }
        }
      }

      Divider()

      // Control bar
      controlBar(viewModel: viewModel)
    }
    .sheet(isPresented: $showScoreboard) {
      ScoreboardSheet(scores: viewModel.scores, eliminated: viewModel.eliminated)
        .presentationDetents([.medium])
        .deepLinkGated()
    }
    // The model-busy scrim (initial load + BG reload) now lives at `body`
    // level as a single persistent overlay so the spinner stays continuous
    // across the scenario→model load handoff — see `body` / `loadingScrim`. (#825)
    .overlay(alignment: LanguageDriftToastLayout.overlayAlignment) {
      languageDriftToast(viewModel: viewModel)
    }
    .animation(.default, value: viewModel.pendingLanguageMismatchToast)
    // "Fill the bar" — title row goes into the system nav bar's
    // principal slot (reclaiming the previously-empty 44pt strip);
    // meta row mounts via `safeAreaInset(.top)` with frosted BG
    // extending up behind the (transparent) bar for visual
    // continuity. See ADR-008 §Amendment 2026-05-10.
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        // Route the back tap through the confirm-on-leave guard (#673).
        // Swipe-back bypasses this (UIKit gesture) and relies on the
        // terminal-ladder `.paused` safety net — see PasturaBackButton's doc.
        PasturaBackButton(action: handleBackTap)
      }
      .hidingPasturaSharedBackground()
      ToolbarItem(placement: .principal) {
        makeHeader(viewModel: viewModel)
          .titleRow
          // Pin a non-collapsing identity for the toolbar item so
          // SwiftUI doesn't re-create / re-animate it on every
          // VM-driven status change.
          .accessibilityIdentifier("simulation.header.title")
      }
      .hidingPasturaSharedBackground()
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      headerMetaInset(viewModel: viewModel)
    }
  }

  /// One-shot toast for the first `.languageMismatch` event of the
  /// current run (#401). Re-runs whenever
  /// ``SimulationViewModel/pendingLanguageMismatchToast`` flips to a
  /// new non-nil value (in practice only once per `run()` cycle, since
  /// the VM's gating on `count == 0` prevents re-fire after dismissal).
  ///
  /// Auto-dismiss after 4 seconds — long enough for a glance, short
  /// enough that a burst doesn't keep the toast pinned. Tone matches
  /// the informational `ultraThinMaterial` capsule used by
  /// `ScenarioEditorView.promptCopiedToast`; ContentFilter has its own
  /// danger surface (ADR-005) which we deliberately do not borrow.
  @ViewBuilder
  private func languageDriftToast(
    viewModel: SimulationViewModel
  ) -> some View {
    if let text = viewModel.languageMismatchToastText {
      Label(text, systemImage: "globe")
        // `.font(.caption)` stays inline: `SwiftUI.Font` is not `Equatable`,
        // so it can't back the `LanguageDriftToastLayout` value-mirror
        // tripwire — it's code-review-gated alongside the rendered surface.
        .font(.caption)
        .padding(.horizontal, LanguageDriftToastLayout.contentHorizontalPadding)
        .padding(.vertical, LanguageDriftToastLayout.contentVerticalPadding)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, LanguageDriftToastLayout.topInset)
        .padding(.horizontal, LanguageDriftToastLayout.edgeHorizontalPadding)
        .transition(.move(edge: .top).combined(with: .opacity))
        // Decorative SF Symbol — `text` already carries the semantic.
        // Matches `GameHeader.metaRow`'s globe badge accessibility.
        .accessibilityLabel(text)
        .task(id: viewModel.pendingLanguageMismatchToast) {
          try? await Task.sleep(for: .seconds(LanguageDriftToastLayout.autoDismissSeconds))
          viewModel.dismissLanguageMismatchToast()
        }
        .accessibilityIdentifier("simulation.languageDriftToast")
    }
  }

  /// The single dimmed loading scrim, shown for scenario load, initial model
  /// load, and BG GPU↔CPU reload — distinguished only by `label`. Mounted once
  /// in `body` and kept alive across the scenario→model handoff.
  ///
  /// LOAD-BEARING ordering: `IdleFriendlyProgressView` is the FIRST child and
  /// carries no `.id` — its stable structural identity is what keeps the
  /// spinner from restarting when only `label` changes. The subtitle is the
  /// conditional element (never the spinner), so toggling it never reshuffles
  /// the progress view's position. (#825)
  private func loadingScrim(_ label: SimulationDisplayState.ScrimLabel) -> some View {
    ZStack {
      Color.ink.opacity(0.4).ignoresSafeArea()
      VStack(spacing: 12) {
        IdleFriendlyProgressView()
          .scaleEffect(1.2)
        Text(scrimTitle(label))
          .textStyle(Typography.titlePhase)
          .foregroundStyle(Color.ink)
        if let subtitle = scrimSubtitle(label) {
          Text(subtitle)
            .textStyle(Typography.metaValue)
            .foregroundStyle(Color.muted)
        }
      }
      .padding(24)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  /// Opening-card model for the current scenario, or `nil` when there is no
  /// premise to show (#853). `title` is `nil`: the header already shows the
  /// scenario name, so the card would only restate it.
  private var introModel: ScenarioIntroCard.Model? {
    ScenarioIntroCard.Model(title: nil, premise: scenario?.description ?? "")
  }

  /// The resolved closing-card outcome, or `nil` when the run has nothing worth
  /// showing (summary-only). The insertion condition short-circuits on
  /// `resultCardVisible` first, so this runs only post-completion (not on every
  /// streaming re-eval); the derivation is pure and O(roster) besides. Takes
  /// the unwrapped `viewModel` (the struct-level `@State` is optional). (#868)
  private func resultModel(viewModel: SimulationViewModel) -> SimulationResultCard.Model? {
    SimulationResultCard.Model(
      scores: viewModel.scores,
      eliminated: viewModel.eliminated,
      voteResults: viewModel.voteResults,
      eliminationVotes: viewModel.eliminationVotes,
      phases: scenario?.phases ?? [])
  }

  /// The viewer-prediction reward badge, shown with the result card once the
  /// run completes and only when the run had an answered prediction (#915).
  /// Extracted from the timeline body to keep its cyclomatic complexity in
  /// budget.
  @ViewBuilder
  private func predictionOutcomeBadge(viewModel: SimulationViewModel) -> some View {
    if resultCardVisible, let outcome = viewModel.predictionOutcome {
      PredictionOutcomeBadge(isHit: outcome.isHit, streak: outcome.streak)
        .transition(.opacity)
    }
  }

  /// Whether any real score exists — gates the closing card's tap-to-scoreboard
  /// affordance (the `ScoreboardSheet` is score-centric; a vote-only outcome
  /// would render misleading all-zero rows).
  private func hasRankableScores(viewModel: SimulationViewModel) -> Bool {
    viewModel.scores.values.contains { $0 != 0 }
  }

  /// `true` for the resume entry (a paused run being reopened). The opening card
  /// renders statically on resume — the typed reveal + its conversation gate are
  /// a fresh-run start beat only (#853).
  private var isResumeEntry: Bool {
    if case .resume = source { return true }
    return false
  }

  /// Typing speed for the opening premise card, or `nil` for the static (no
  /// typing) path. Pure so the reveal-gate logic is unit-tested (ADR-009):
  /// - Resume entries (`isResumeEntry`) never re-play the reveal beat.
  /// - Once the reveal has begun (`introRevealHasBegun`, a VM latch that
  ///   survives an ADR-017 Phase B adopt re-projection), the card is static so
  ///   returning to a parked run doesn't re-type the premise (#934).
  /// - Otherwise it types at the playback speed (`.instant` passes `nil` here,
  ///   collapsing to the static path).
  static func premiseCharsPerSecond(
    isResumeEntry: Bool, introRevealHasBegun: Bool, speedCharsPerSecond: Double?
  ) -> Double? {
    (isResumeEntry || introRevealHasBegun) ? nil : speedCharsPerSecond
  }

  /// A short "held breath" before the premise starts typing so the reveal
  /// doesn't begin abruptly on mount (#853). Scaled inversely with playback
  /// speed via `multiplier` (slow ⇒ longer, fast ⇒ shorter); `.instant`'s
  /// infinite multiplier collapses it to `.zero`, matching its static reveal.
  private func introLeadIn(for speed: PlaybackSpeed) -> Duration {
    let baseSeconds = 0.45
    let multiplier = speed.multiplier
    guard multiplier.isFinite, multiplier > 0 else { return .zero }
    return .seconds(baseSeconds / multiplier)
  }

  private func scrimTitle(_ label: SimulationDisplayState.ScrimLabel) -> String {
    switch label {
    case .scenario: String(localized: "Loading scenario...")
    case .model: String(localized: "Loading model...")
    case .reload: String(localized: "Reloading model...")
    }
  }

  /// Scenario load is typically sub-second, so it omits the "few seconds"
  /// subtitle (which would misrepresent the wait); model load / reload keep it.
  private func scrimSubtitle(_ label: SimulationDisplayState.ScrimLabel) -> String? {
    switch label {
    case .scenario: nil
    case .model, .reload: String(localized: "This can take a few seconds")
    }
  }

  // MARK: - Header

  /// Sim composition of the shared `GameHeader`. Sim uses the
  /// **split** rendering — title row hosted in `ToolbarItem(.principal)`,
  /// meta row mounted via `safeAreaInset(.top)`. Demo's
  /// `+GameHeader.swift` extension uses the unified `body` instead
  /// (it's hosted in `.fullScreenCover` with no nav bar above).
  /// See `Views/Components/GameHeader.swift` for the rendering-modes
  /// contract and ADR-008 §Amendment 2026-05-10 for the "fill the
  /// bar" pivot rationale.
  ///
  /// Inputs:
  /// - `scenarioName` / `initialName` — the 3-tier fallback chain.
  ///   ADR-008 §Amendment 2026-04-29 documents the sink pivot from
  ///   `.navigationTitle()` to GameHeader's row 1.
  /// - `round` — `viewModel.headerRound` (`GameHeaderRound?`). Real
  ///   game-rounds from `.roundStarted` events; pair-or-nothing
  ///   guard lives on the VM (#313). Suppressed (nil) until the
  ///   first `.roundStarted` lands so ROUND doesn't flash a stale
  ///   `0/0` between scenario load and first round.
  /// - `phaseLabel` — formatted from `viewModel.currentPhase`.
  /// - `tokensPerSecond` — `averageTokensPerSecond` (live moving
  ///   average).
  /// - `extendsIntoTopSafeArea: false` — irrelevant for the split
  ///   rendering (the unified `body` is not used). Sim's frosted
  ///   continuity comes from `headerMetaInset`'s background ignoring
  ///   the top safe area.
  private func makeHeader(viewModel: SimulationViewModel) -> GameHeader {
    GameHeader(
      scenarioName: scenario?.name,
      initialName: initialName,
      status: viewModel.status,
      round: viewModel.headerRound,
      phaseLabel: viewModel.currentPhase.map(PhaseDisplayName.label(for:)),
      tokensPerSecond: viewModel.averageTokensPerSecond,
      extendsIntoTopSafeArea: false
    )
  }

  /// Meta-row inset content + frosted background that fills behind
  /// the (transparent) nav bar via `.ignoresSafeArea(.container,
  /// edges: .top)`. Always renders the BG strip (even when the meta
  /// row collapses to empty for late-load / completion states), so
  /// the principal-slot title above always sits over a frosted
  /// surface — the visual unification that addresses #312's
  /// cramped-stream finding.
  ///
  /// Padding: 18pt horizontal matches `GameHeader.headerInsets`
  /// (HEADER_UPDATE.md design hand-off); vertical is asymmetric
  /// (small top, full bottom) because the principal slot above
  /// already provides the title row's vertical breathing room.
  /// Bottom 1pt overlay rule mirrors the unified `body`'s
  /// `Color.ink.opacity(0.07)` divider so split and unified
  /// renderings share the same delineation against the chat stream.
  private func headerMetaInset(
    viewModel: SimulationViewModel
  ) -> some View {
    let header = makeHeader(viewModel: viewModel)
    return Group {
      if header.hasMetaRow {
        header.metaRow
          .padding(.horizontal, 18)
          .padding(.top, 4)
          .padding(.bottom, 8)
      } else {
        // Pre-load and post-completion states can land here with all
        // three meta-row inputs nil. The inset must still have positive
        // layout height for its frosted background's
        // `.ignoresSafeArea(.container, edges: .top)` to anchor and
        // paint behind the (transparent) nav bar — otherwise the
        // principal-slot title would sit naked over scrolling chat
        // content. A 1pt invisible spacer is the minimal anchor.
        Color.clear.frame(height: 1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      ZStack {
        Color.screenBackground.opacity(0.78)
        Rectangle().fill(.ultraThinMaterial)
      }
      .ignoresSafeArea(.container, edges: .top)
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.ink.opacity(0.07))
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("simulation.header.meta")
  }

  // MARK: - Log Entries

  @ViewBuilder
  private func logEntryView(
    _ entry: LogEntry, viewModel: SimulationViewModel, proxy: ScrollViewProxy
  ) -> some View {
    switch entry.kind {
    case .agentOutput(let agent, let output, let phaseType):
      let isLatest = viewModel.latestAgentOutputId == entry.id
      AgentOutputRow(
        agent: agent, output: output, phaseType: phaseType,
        showAllThoughts: viewModel.showAllThoughts,
        isLatest: isLatest,
        // Display timing is a VM decision. A streamed row is NOT snapped —
        // it animates from its handoff seed (see `initialVisibleChars`).
        charsPerSecond: viewModel.effectiveCharsPerSecond(forEntryId: entry.id),
        // Only the latest row drives the typing-state gate; older rows
        // never animate so their callbacks would be no-ops, but we guard
        // here anyway to keep the signal unambiguous.
        onAnimatingChange: { animating in
          guard isLatest else { return }
          latestRowIsAnimating = animating
        },
        // Follow the latest row's growth while it types its tail / thought
        // from the handoff seed (the bubble grows under `growsWithReveal`).
        // Gated to the latest row so scrolling up through history never
        // yanks back to the bottom.
        onRevealProgress: {
          if isLatest { scrollToBottom(proxy) }
        },
        // Record the latest row's reveal completion on the VM so an ADR-017
        // Phase B adopt re-projection renders it static instead of re-typing
        // (#934). Guarded to the latest row; the VM re-guards on entry id.
        onRevealCompleted: {
          if isLatest { viewModel.markLatestRowRevealCompleted(entryId: entry.id) }
        },
        // Grow the bubble with the revealed prefix so the handoff from the
        // streaming row is seamless (self-gates: only the latest animating
        // row grows; older rows reserve full layout via shouldReserveHiddenTail).
        growsWithReveal: true,
        // Continue typing from where the stream left off instead of snapping
        // (reveal-position handoff, bug 2); 0 for a non-streamed row.
        initialVisibleChars: viewModel.handoffSeed(forEntryId: entry.id),
        agentPosition: scenario?.personas.firstIndex(where: { $0.name == agent }),
        debugRowID: entry.id.uuidString
      )
    case .phaseStarted(let phaseType):
      // LLM phases (speak / vote / choose) become full-width separators
      // so the transcript chunks into phase "chapters" (#882); code
      // phases keep the inline badge to avoid over-chunking
      // code-phase-heavy scenarios.
      if phaseType.requiresLLM {
        phaseSeparator(phaseType)
      } else {
        PhaseTypeLabel(phaseType: phaseType)
          .padding(.top, 4)
      }
    case .roundStarted(let round, let total):
      // Reuses the `Round %lld / %lld` key already wired into GameHeader
      // so the round-separator label and header label stay translation-aligned.
      roundSeparator(String(format: String(localized: "Round %lld / %lld"), round, total))
    case .roundCompleted(_, let scores), .scoreUpdate(let scores):
      scoresSummary(scores)
    case .error(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .textStyle(Typography.titlePhase)
        .foregroundStyle(Color.inkSecondary)
    default:
      secondaryLogEntryView(entry)
    }
  }

  @ViewBuilder
  private func secondaryLogEntryView(_ entry: LogEntry) -> some View {
    switch entry.kind {
    case .elimination(let agent, let voteCount):
      eliminationEntry(agent: agent, voteCount: voteCount)
    case .assignment(let agent, let value):
      assignmentEntry(agent: agent, value: value)
    case .summary(let text):
      summaryEntry(text: text)
    case .voteResults(_, let tallies):
      voteResultsEntry(tallies: tallies)
    case .pairingResult(let agent1, let act1, let agent2, let act2):
      pairingResultEntry(agent1: agent1, act1: act1, agent2: agent2, act2: act2)
    case .eventInjected(let event):
      eventInjectedEntry(event: event)
    default:
      EmptyView()
    }
  }

  // MARK: - Controls

  // Shared width so the control slot doesn't jump when the simulation
  // completes and the Speed menu is swapped for the Export button.
  // `minWidth` (not exact) so Dynamic Type / future localization can expand.
  private static let controlSlotMinWidth: CGFloat = 110

  /// Identifier for the invisible bottom sentinel used by auto-scroll.
  private static let bottomSentinelID = "pastura.simulation.log.bottom"

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    withAnimation {
      proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
    }
  }

  @ViewBuilder
  private func speedOrExportControl(viewModel: SimulationViewModel) -> some View {
    if viewModel.isCompleted {
      Button {
        Task { await triggerExport(viewModel: viewModel) }
      } label: {
        if isExporting {
          IdleFriendlyProgressView().frame(minWidth: Self.controlSlotMinWidth)
        } else {
          Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
            .font(.title3)
            .frame(minWidth: Self.controlSlotMinWidth)
        }
      }
      .disabled(isExporting)
    } else {
      // Menu + explicit Button rows instead of Menu-wrapped Picker or
      // Picker.pickerStyle(.menu). Both of those trigger SwiftUI quirks on
      // iOS 17/18: the nested Picker logs `_UIReparentingView` warnings,
      // and `.pickerStyle(.menu) + .labelsHidden()` reserves internal
      // label space that wraps short selections like "x1" to a second line.
      // Manual Button rows with a checkmark on the active choice side-step
      // both and keep full control of the trigger layout.
      Menu {
        ForEach(PlaybackSpeed.allCases) { speed in
          Button {
            viewModel.speed = speed
          } label: {
            if speed == viewModel.speed {
              Label(speed.label, systemImage: "checkmark")
            } else {
              Text(speed.label)
            }
          }
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "gauge.with.dots.needle.50percent")
          Text(viewModel.speed.label)
          Image(systemName: "chevron.down")
            .font(.caption2)
        }
        .textStyle(Typography.titlePhase)
        .frame(minWidth: Self.controlSlotMinWidth)
      }
    }
  }

  /// Pause/Resume — a filled `mossDark` circle + white glyph (see
  /// ``SimulationPlayButtonMetrics``) rather than a bare glyph: the lone
  /// filled symbol used to read as a stray "black blob" on the frosted bar.
  /// `disabledText` fill when disabled. No circle shadow — the frosted bar
  /// already lifts (design-system §1/§4.3 single floating element; avoid
  /// double-lift).
  private func playPauseButton(viewModel: SimulationViewModel, isDisabled: Bool) -> some View {
    Button {
      if viewModel.isPaused {
        viewModel.resumeSimulation()
      } else {
        viewModel.pauseSimulation()
      }
    } label: {
      Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
        .font(.system(size: SimulationPlayButtonMetrics.glyphPointSize, weight: .semibold))
        .foregroundStyle(SimulationPlayButtonMetrics.glyphColor)
        .frame(
          width: SimulationPlayButtonMetrics.diameter,
          height: SimulationPlayButtonMetrics.diameter
        )
        .background(
          isDisabled
            ? SimulationPlayButtonMetrics.disabledFill
            : SimulationPlayButtonMetrics.enabledFill,
          in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
  }

  private func controlBar(viewModel: SimulationViewModel) -> some View {
    let isPauseDisabled = !viewModel.isRunning || viewModel.isCompleted
    return HStack(spacing: 16) {
      playPauseButton(viewModel: viewModel, isDisabled: isPauseDisabled)

      // Speed picker while running; swapped with an export button once the
      // simulation is completed because playback speed is no longer relevant.
      speedOrExportControl(viewModel: viewModel)

      Spacer()

      // Thought visibility toggle — uses ThoughtVisibilityToggle from Components
      // for parity with Results / Demo (issue #273).
      @Bindable var viewModel = viewModel
      ThoughtVisibilityToggle(isOn: $viewModel.showAllThoughts)
        .font(.title3)

      // Background continuation toggle (iOS 26+ with LlamaCppService only)
      if #available(iOS 26, *), viewModel.canEnableBackgroundContinuation {
        backgroundContinuationToggle(viewModel: viewModel)
      }

      // Scoreboard
      Button {
        showScoreboard = true
      } label: {
        Image(systemName: "chart.bar.fill")
          .font(.title3)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background {
      // `ignoresSafeArea(.container, edges: .bottom)` extends the
      // tinted background into the home-indicator inset. Without it,
      // the safe-area strip below the control bar renders as raw
      // system white, breaking the frosted-bar illusion. The HStack
      // content (buttons) stays within the safe area because only
      // the background layer opts out — not the foreground.
      ZStack {
        Color.screenBackground.opacity(0.78)
        Rectangle().fill(.ultraThinMaterial)
      }
      .ignoresSafeArea(.container, edges: .bottom)
    }
    .overlay(alignment: .top) {
      Rectangle().fill(Color.ink.opacity(0.07)).frame(height: 1)
    }
  }

  // MARK: - Load & Run

  /// Fresh-run entry: fetch the scenario, parse it, and start `run()` via the
  /// app-level session (``startOwnedRun(_:body:)``).
  private func loadAndRun(scenarioId: String) async {
    let deps = dependencies
    do {
      guard
        let record = try await offMain({
          try deps.scenarioRepository.fetchById(scenarioId)
        })
      else {
        loadError = String(localized: "Scenario not found")
        return
      }
      let parsed = try ScenarioLoader().load(yaml: record.yamlDefinition)
      // Thread the gallery category from the record we already hold (#748) so
      // the run snapshots it without a refetch-by-id — category is gallery
      // metadata not present in the parsed YAML. nil for local scenarios.
      let categorySnapshot = record.category
      // Arm the intro gate iff an opening card will actually render — using the
      // SAME empty-premise guard the card uses (`ScenarioIntroCard.Model`), so
      // the VM never waits on a reveal that never happens (#853, critic Axis 4).
      // Size the gate's last-resort backstop above the real reveal time
      // (premise length ÷ the slowest playback speed + buffer) so it never
      // clips a long premise typing at slow speed, yet still can't hang forever.
      let hasIntroCard = ScenarioIntroCard.Model(title: nil, premise: parsed.description) != nil
      let slowestCps = PlaybackSpeed.slow.charsPerSecond ?? 6
      let introBackstop: TimeInterval? =
        hasIntroCard ? Double(parsed.description.count) / slowestCps + 15 : nil
      startOwnedRun(parsed, armIntroBackstop: introBackstop) { model in
        await model.run(
          scenario: parsed, llm: deps.llmService,
          scenarioCategorySnapshot: categorySnapshot)
      }
    } catch {
      loadError = error.localizedDescription
    }
  }

  /// Resume entry (ADR-016 P3, #667): resolve the paused run + the scenario it
  /// actually ran against (snapshot-preferred, live fallback — the same
  /// ``ScenarioSnapshotResolver`` the export / past-results paths use, so a
  /// since-edited or -deleted live scenario can't drift the resumed run), then
  /// start `resume(record:scenario:llm:)` via the app-level session
  /// (``startOwnedRun(_:body:)``).
  private func loadAndResume(runId: String) async {
    let deps = dependencies
    do {
      let resolved: (SimulationRecord, ScenarioRecord)? = try await offMain {
        guard
          let record = try deps.simulationRepository.fetchById(runId),
          let scenarioRecord = try ScenarioSnapshotResolver.resolve(
            for: record, liveLookup: deps.scenarioRepository.fetchById)
        else { return nil }
        return (record, scenarioRecord)
      }
      guard let (record, scenarioRecord) = resolved else {
        loadError = String(localized: "Paused run not found")
        return
      }
      let parsed = try ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition)
      startOwnedRun(parsed) { model in
        await model.resume(record: record, scenario: parsed, llm: deps.llmService)
      }
    } catch {
      loadError = error.localizedDescription
    }
  }

  /// Constructs the live `SimulationViewModel` shared by both entries.
  ///
  /// ADR-010 Step E PR2 — the production runner gets the `NLLanguageDetector`
  /// so adherence retry + `.languageMismatch` are live. Injected here at the
  /// View boundary (not as a VM `init` default) so fixture tests that build the
  /// VM directly keep pre-Step E retry semantics (`.claude/rules/swiftui-traps.md`
  /// § "Production-side-effecting service").
  private func makeViewModel() -> SimulationViewModel {
    let deps = dependencies
    return SimulationViewModel(
      runner: SimulationRunner(detector: NLLanguageDetector()),
      simulationRepository: deps.simulationRepository,
      turnRepository: deps.turnRepository,
      codePhaseEventRepository: deps.codePhaseEventRepository,
      scenarioRepository: deps.scenarioRepository,
      predictionRepository: deps.predictionRepository,
      backgroundManager: deps.backgroundManager,
      simulationActivityRegistry: deps.simulationActivityRegistry
    )
  }

  /// Starts a run owned by the app-level ``SimulationSession`` and projects it
  /// into local `@State` for rendering.
  ///
  /// Phase B (ADR-017) PR1: ownership of the driving task moves to the session
  /// (relocated from the former `drive(_:_:)`), so the run can outlive the view
  /// (PR2). The run is still ended on `onDisappear`, so behaviour is unchanged.
  /// The session's `startGuarded` is the start-time single-run guard that
  /// replaces cancel-on-disappear as the invariant's enforcer once ownership is
  /// lifted.
  private func startOwnedRun(
    _ parsed: Scenario,
    armIntroBackstop: TimeInterval? = nil,
    body: @escaping (SimulationViewModel) async -> Void
  ) {
    let session = dependencies.simulationSession
    switch session.startGuarded(
      source: source,
      scenario: parsed,
      tab: tabCoordinator.selectedTab,
      makeViewModel: makeViewModel,
      body: body
    ) {
    case .started:
      // `startGuarded` spawns the run task before this returns, but the task
      // first suspends at an `await` inside `run()` and `SimulationSession` is
      // `@MainActor`, so no observable state mutates before these synchronous
      // @State assignments complete on the same MainActor run loop — no flash.
      // `body`'s `if let viewModel, scenario != nil` gate also guards a
      // half-projected frame.
      scenario = parsed
      viewModel = session.viewModel
      // Arm the intro gate synchronously, before `run()` reaches
      // `awaitIntroReveal()` (it first suspends at model load). Set here — not
      // in `run()` — so the View stays the single owner of the premise-card
      // predicate that both arms the gate and renders the card (#853).
      if let armIntroBackstop {
        session.viewModel?.beginIntro(revealBackstop: armIntroBackstop)
      }
    case .refusedLiveRunExists:
      // PR1: structurally unreachable — `onDisappear` → `session.end()` frees
      // the slot before any second start. The "already running" + Return-to-run
      // UI lands in PR2 with the in-flight indicator.
      Self.logger.warning("startGuarded refused: a run is already owned; ignoring (PR1)")
    }
  }

  private func triggerExport(viewModel: SimulationViewModel) async {
    isExporting = true
    defer { isExporting = false }

    let env = ResultMarkdownExporter.ExportEnvironment(
      deviceModel: UIDevice.current.model,
      osVersion: ResultMarkdownExporter.ExportEnvironment.normalizeOSVersion(
        ProcessInfo.processInfo.operatingSystemVersionString))
    do {
      let payload = try await viewModel.fetchExportPayload(exportEnvironment: env)
      exportPayload = payload
    } catch {
      exportError = error.localizedDescription
    }
  }
}

// Log-entry helpers live in SimulationView+LogEntries.swift.
