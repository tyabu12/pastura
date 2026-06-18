// swiftlint:disable file_length
// Deliberately long: this view orchestrates the entire live simulation
// surface — header, log + typing + thinking indicators, scroll handling,
// control bar, scoreboard sheet, export flow, and lifecycle hooks. Log-
// entry rendering is already split into SimulationView+LogEntries.swift;
// further extraction would scatter state bindings across files.
import SwiftUI
import UIKit

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
  @State private var viewModel: SimulationViewModel?
  /// `true` while the back-button confirm-on-leave dialog is showing (#673).
  @State private var pendingBackLeave = false
  // Accessed from SimulationView+Background.swift extension for the toggle subtitle.
  @State var scenario: Scenario?
  @State private var showScoreboard = false
  @State private var loadError: String?
  @State private var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State private var exportError: String?
  @State private var isExporting = false
  @State private var memoryThrottle = MemoryWarningThrottle()
  /// Whether the latest agent-output row is still typing. Used to suppress
  /// "X is thinking..." indicators so they don't appear above text that's
  /// still being revealed.
  @State private var latestRowIsAnimating = false

  var body: some View {
    Group {
      if let viewModel, scenario != nil {
        simulationContent(viewModel: viewModel)
      } else if let loadError {
        ContentUnavailableView(
          String(localized: "Error"),
          systemImage: "exclamationmark.triangle",
          description: Text(loadError)
        )
      } else {
        ProgressView(String(localized: "Loading scenario..."))
      }
    }
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
    .task {
      switch source {
      case .scenario(let scenarioId):
        await loadAndRun(scenarioId: scenarioId)
      case .resume(let runId):
        await loadAndResume(runId: runId)
      }
    }
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
      // Policy in MemoryWarningThrottle. See that file for rationale.
      guard let viewModel, viewModel.isRunning, !viewModel.isCancelled else { return }
      let decision = memoryThrottle.decide(
        isActive: scenePhase == .active, isPaused: viewModel.isPaused, now: Date()
      )
      switch decision {
      case .ignore: break
      case .pauseAndLog:
        viewModel.pauseSimulation(
          reason: String(
            localized: "Memory warning — simulation paused. Tap resume to continue.")
        )
      case .cancelDueToBackground:
        viewModel.cancelSimulation(caller: "memoryWarning-bg")
      case .cancelDueToEscalation:
        viewModel.cancelSimulation(caller: "memoryWarning-escalated")
      }
    }
    .onChange(of: viewModel?.isPaused ?? false) { _, isPaused in
      // After the user resumes, treat the previous pressure as resolved so a
      // delayed warning doesn't immediately escalate to cancel (closes the
      // "user just resumed and got cancelled" trap from critic Axis 2).
      if !isPaused { memoryThrottle.reset() }
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
    // Back-button confirm-on-leave (#673). The back button raises the dialog
    // via `handleBackTap()`. Focus mode (ADR-017) hides the tab bar during a
    // run, so a mid-run tab switch — and the TabCoordinator defer path it used
    // to need — is impossible; only the back path remains.
    .alert(
      String(localized: "A simulation is in progress"),
      isPresented: leaveAlertBinding
    ) {
      Button(String(localized: "Pause and leave")) { confirmLeave() }
      Button(String(localized: "Stay"), role: .cancel) { stay() }
    } message: {
      Text(String(localized: "Pause and save it so you can resume later?"))
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

  /// Back-button tap (#673). Confirm first when a run is in flight; otherwise
  /// pop immediately.
  private func handleBackTap() {
    if leaveGuardActive {
      pendingBackLeave = true
    } else {
      router.pop()
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
  /// tab's stack. Only the back path reaches here — swipe-back bypasses the
  /// dialog, and a tab switch is impossible under focus mode (ADR-017).
  private func confirmLeave() {
    viewModel?.pauseSimulation()
    router.pop()
    pendingBackLeave = false
  }

  /// "Stay": discard the pending leave and keep running.
  private func stay() {
    pendingBackLeave = false
  }

  private func simulationContent(  // swiftlint:disable:this function_body_length
    viewModel: SimulationViewModel
  ) -> some View {
    VStack(spacing: 0) {
      // Log
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: ChatBubbleLayout.bubbleSpacing) {
            ForEach(viewModel.logEntries) { entry in
              logEntryView(entry, viewModel: viewModel)
                .id(entry.id)
            }

            // Live streaming row for the in-flight inference (if any).
            // Appears once the partial parser has confirmed the primary
            // key's opening quote; before that, the "thinking" indicator
            // below stays visible. Rendered ABOVE the thinking indicators
            // so users never see "X is thinking..." and live tokens for
            // X at the same time.
            if let snapshot = viewModel.streamingSnapshot {
              AgentOutputRow(
                agent: snapshot.agent,
                output: TurnOutput(fields: [:]),
                phaseType: snapshot.phaseType,
                showAllThoughts: viewModel.showAllThoughts,
                isLatest: false,
                charsPerSecond: viewModel.speed.charsPerSecond,
                streamingPrimary: snapshot.primary,
                streamingThought: snapshot.thought,
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
                  ProgressView()
                    .scaleEffect(0.7)
                  Text(String(format: String(localized: "%@ is thinking..."), agent))
                    .textStyle(Typography.thinkingBody)
                    .foregroundStyle(Color.muted)
                }
              }
            }

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
    .overlay {
      if viewModel.isReloadingModel {
        modelReloadingOverlay
      }
    }
    .overlay(alignment: .top) {
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
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        // Decorative SF Symbol — `text` already carries the semantic.
        // Matches `GameHeader.metaRow`'s globe badge accessibility.
        .accessibilityLabel(text)
        .task(id: viewModel.pendingLanguageMismatchToast) {
          try? await Task.sleep(for: .seconds(4))
          viewModel.dismissLanguageMismatchToast()
        }
        .accessibilityIdentifier("simulation.languageDriftToast")
    }
  }

  private var modelReloadingOverlay: some View {
    ZStack {
      Color.ink.opacity(0.4).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView()
          .scaleEffect(1.2)
        Text(String(localized: "Reloading model..."))
          .textStyle(Typography.titlePhase)
          .foregroundStyle(Color.ink)
        Text(String(localized: "This can take a few seconds"))
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.muted)
      }
      .padding(24)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .transition(.opacity)
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
  private func logEntryView(_ entry: LogEntry, viewModel: SimulationViewModel) -> some View {
    switch entry.kind {
    case .agentOutput(let agent, let output, let phaseType):
      let isLatest = viewModel.latestAgentOutputId == entry.id
      AgentOutputRow(
        agent: agent, output: output, phaseType: phaseType,
        showAllThoughts: viewModel.showAllThoughts,
        isLatest: isLatest,
        // Display timing is a VM decision — rows whose primary was
        // already revealed via streaming must not retype (returns nil).
        charsPerSecond: viewModel.effectiveCharsPerSecond(forEntryId: entry.id),
        // Only the latest row drives the typing-state gate; older rows
        // never animate so their callbacks would be no-ops, but we guard
        // here anyway to keep the signal unambiguous.
        onAnimatingChange: { animating in
          guard isLatest else { return }
          latestRowIsAnimating = animating
        },
        agentPosition: scenario?.personas.firstIndex(where: { $0.name == agent }),
        debugRowID: entry.id.uuidString
      )
    case .phaseStarted(let phaseType):
      PhaseTypeLabel(phaseType: phaseType)
        .padding(.top, 4)
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
          ProgressView().frame(minWidth: Self.controlSlotMinWidth)
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

  private func controlBar(viewModel: SimulationViewModel) -> some View {
    let isPauseDisabled = !viewModel.isRunning || viewModel.isCompleted
    return HStack(spacing: 16) {
      // Pause/Resume
      Button {
        if viewModel.isPaused {
          viewModel.resumeSimulation()
        } else {
          viewModel.pauseSimulation()
        }
      } label: {
        // Explicit `Color.disabledText` (design-system §2.7) when
        // disabled, matching Demo's controlBar (#273 PR 1a). Enabled
        // state uses `Color.ink` for the icon color rather than the
        // system tint so the bar's color story stays in our palette.
        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
          .font(.title3)
          .foregroundStyle(isPauseDisabled ? Color.disabledText : Color.ink)
      }
      .disabled(isPauseDisabled)

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

  /// Fresh-run entry: fetch the scenario, parse it, and drive `run()`.
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
      scenario = parsed
      let simViewModel = makeViewModel()
      viewModel = simViewModel
      await drive(simViewModel) {
        await simViewModel.run(scenario: parsed, llm: deps.llmService)
      }
    } catch {
      loadError = error.localizedDescription
    }
  }

  /// Resume entry (ADR-016 P3, #667): resolve the paused run + the scenario it
  /// actually ran against (snapshot-preferred, live fallback — the same
  /// ``ScenarioSnapshotResolver`` the export / past-results paths use, so a
  /// since-edited or -deleted live scenario can't drift the resumed run), then
  /// drive `resume(record:scenario:llm:)`.
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
      scenario = parsed
      let simViewModel = makeViewModel()
      viewModel = simViewModel
      await drive(simViewModel) {
        await simViewModel.resume(record: record, scenario: parsed, llm: deps.llmService)
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
      backgroundManager: deps.backgroundManager,
      simulationActivityRegistry: deps.simulationActivityRegistry
    )
  }

  /// Drives `body` (a `run` / `resume` call) on an unstructured Task wired for
  /// cancellation propagation.
  ///
  /// `Task { }` is unstructured and does not inherit `.task` cancellation, so a
  /// plain `await runTask.value` would leak the run when the user navigates
  /// back — the old run keeps driving the shared `LLMService` while a newly
  /// pushed `SimulationView` starts its own, corrupting model state. The
  /// `runTask` reference also lets `cancelSimulation()` (e.g. memory warning)
  /// stop the run.
  private func drive(
    _ viewModel: SimulationViewModel, _ body: @escaping () async -> Void
  ) async {
    let runTask = Task { await body() }
    viewModel.runTask = runTask
    await withTaskCancellationHandler {
      await runTask.value
    } onCancel: {
      runTask.cancel()
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
