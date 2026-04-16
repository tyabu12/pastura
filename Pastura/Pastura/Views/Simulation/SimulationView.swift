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
  let scenarioId: String

  @Environment(\.scenePhase) private var scenePhase
  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: SimulationViewModel?
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
          "Error",
          systemImage: "exclamationmark.triangle",
          description: Text(loadError)
        )
      } else {
        ProgressView("Loading scenario...")
      }
    }
    .navigationTitle(scenario?.name ?? "Simulation")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadAndRun()
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
          reason: "Memory warning — simulation paused. Tap resume to continue."
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
      "Export failed",
      isPresented: Binding(
        get: { exportError != nil },
        set: { if !$0 { exportError = nil } }
      )
    ) {
      Button("OK", role: .cancel) { exportError = nil }
    } message: {
      Text(exportError ?? "")
    }
  }

  private func simulationContent(  // swiftlint:disable:this function_body_length
    viewModel: SimulationViewModel
  ) -> some View {
    VStack(spacing: 0) {
      // Header bar
      headerBar(viewModel: viewModel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulation.header")

      Divider()

      // Log
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.logEntries) { entry in
              logEntryView(entry, viewModel: viewModel)
                .id(entry.id)
            }

            // Thinking indicators — suppressed while the latest row is still
            // typing, so "X is thinking..." doesn't jump ahead of text the
            // user is still reading.
            if !latestRowIsAnimating {
              ForEach(Array(viewModel.thinkingAgents), id: \.self) { agent in
                HStack(spacing: 8) {
                  ProgressView()
                    .scaleEffect(0.7)
                  Text("\(agent) is thinking...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
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
      }

      Divider()

      // Control bar
      controlBar(viewModel: viewModel)
    }
    .sheet(isPresented: $showScoreboard) {
      ScoreboardSheet(scores: viewModel.scores, eliminated: viewModel.eliminated)
        .presentationDetents([.medium])
    }
    .overlay {
      if viewModel.isReloadingModel {
        modelReloadingOverlay
      }
    }
  }

  private var modelReloadingOverlay: some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView()
          .scaleEffect(1.2)
        Text("Reloading model...")
          .font(.subheadline)
        Text("This can take a few seconds")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(24)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .transition(.opacity)
  }

  // MARK: - Header

  private func headerBar(viewModel: SimulationViewModel) -> some View {
    HStack {
      if viewModel.totalRounds > 0 {
        Text("Round \(viewModel.currentRound)/\(viewModel.totalRounds)")
          .font(.subheadline.monospacedDigit())
      }

      Spacer()

      inferenceStatsLabel(viewModel: viewModel)

      if viewModel.isCompleted {
        Label("Completed", systemImage: "checkmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.green)
      } else if viewModel.isPaused {
        Label("Paused", systemImage: "pause.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.orange)
      } else if viewModel.isRunning {
        HStack(spacing: 4) {
          ProgressView()
            .scaleEffect(0.7)
          Text("Running")
            .font(.subheadline)
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  @ViewBuilder
  private func inferenceStatsLabel(viewModel: SimulationViewModel) -> some View {
    let duration = viewModel.lastInferenceDurationSeconds
    let tps = viewModel.averageTokensPerSecond
    if duration != nil || tps != nil {
      HStack(spacing: 4) {
        Image(systemName: "speedometer")
          .font(.caption)
        Text(formatInferenceStats(durationSeconds: duration, tokensPerSecond: tps))
          .font(.caption.monospacedDigit())
      }
      .foregroundStyle(.secondary)
    }
  }

  private func formatInferenceStats(
    durationSeconds: Double?, tokensPerSecond: Double?
  ) -> String {
    let tpsPart = tokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "— tok/s"
    let durationPart = durationSeconds.map { String(format: "%.1fs", $0) } ?? "—"
    return "\(tpsPart) • \(durationPart)"
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
        charsPerSecond: viewModel.speed.charsPerSecond,
        // Only the latest row drives the typing-state gate; older rows
        // never animate so their callbacks would be no-ops, but we guard
        // here anyway to keep the signal unambiguous.
        onAnimatingChange: { animating in
          guard isLatest else { return }
          latestRowIsAnimating = animating
        }
      )
      .padding(.horizontal)
    case .phaseStarted(let phaseType):
      PhaseTypeLabel(phaseType: phaseType)
        .padding(.horizontal)
        .padding(.top, 4)
    case .roundStarted(let round, let total):
      roundSeparator("Round \(round)/\(total)")
    case .roundCompleted(_, let scores), .scoreUpdate(let scores):
      scoresSummary(scores)
    case .error(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline)
        .foregroundStyle(.red)
        .padding(.horizontal)
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
          Label("Export", systemImage: "square.and.arrow.up")
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
        .font(.subheadline)
        .frame(minWidth: Self.controlSlotMinWidth)
      }
    }
  }

  private func controlBar(viewModel: SimulationViewModel) -> some View {
    HStack(spacing: 16) {
      // Pause/Resume
      Button {
        if viewModel.isPaused {
          viewModel.resumeSimulation()
        } else {
          viewModel.pauseSimulation()
        }
      } label: {
        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
          .font(.title3)
      }
      .disabled(!viewModel.isRunning || viewModel.isCompleted)

      // Speed picker while running; swapped with an export button once the
      // simulation is completed because playback speed is no longer relevant.
      speedOrExportControl(viewModel: viewModel)

      Spacer()

      // Thought visibility toggle
      Button {
        viewModel.showAllThoughts.toggle()
      } label: {
        Image(systemName: viewModel.showAllThoughts ? "text.bubble.fill" : "text.bubble")
          .font(.title3)
          .foregroundStyle(viewModel.showAllThoughts ? .purple : .secondary)
      }

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
    .background(.bar)
  }

  // MARK: - Load & Run

  private func loadAndRun() async {
    let loader = ScenarioLoader()
    let deps = dependencies
    do {
      guard
        let record = try await offMain({
          try deps.scenarioRepository.fetchById(scenarioId)
        })
      else {
        loadError = "Scenario not found"
        return
      }

      let parsed = try loader.load(yaml: record.yamlDefinition)
      scenario = parsed

      let simViewModel = SimulationViewModel(
        simulationRepository: deps.simulationRepository,
        turnRepository: deps.turnRepository,
        codePhaseEventRepository: deps.codePhaseEventRepository,
        scenarioRepository: deps.scenarioRepository,
        backgroundManager: deps.backgroundManager
      )
      viewModel = simViewModel

      // Store task reference so cancelSimulation() (e.g., on memory warning) works.
      let runTask = Task {
        await simViewModel.run(scenario: parsed, llm: deps.llmService)
      }
      simViewModel.runTask = runTask
      // Propagate `.task` cancellation to `runTask`. `Task { }` is unstructured
      // and does not inherit cancellation, so a plain `await runTask.value`
      // would leak the simulation when the user navigates back from this view
      // — the old run() keeps driving the shared LLMService while a newly
      // pushed SimulationView starts its own run(), corrupting the model state.
      await withTaskCancellationHandler {
        await runTask.value
      } onCancel: {
        runTask.cancel()
      }
    } catch {
      loadError = error.localizedDescription
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
