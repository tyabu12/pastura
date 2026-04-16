import SwiftUI
import UIKit

/// Live simulation execution screen with real-time log, controls, and scoreboard.
struct SimulationView: View {  // swiftlint:disable:this type_body_length
  let scenarioId: String

  @Environment(\.scenePhase) private var scenePhase
  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: SimulationViewModel?
  @State private var scenario: Scenario?
  @State private var showScoreboard = false
  @State private var loadError: String?
  @State private var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State private var exportError: String?
  @State private var isExporting = false

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
      // Pause simulation when app moves to background (ADR-002 §7)
      if newPhase == .background, let viewModel, viewModel.isRunning {
        viewModel.isPaused = true
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didReceiveMemoryWarningNotification
      )
    ) { _ in
      // Memory warning: cancel simulation to free model memory (ADR-002 §7).
      // Cancellation triggers stream termination → for-await exit → unloadModel.
      viewModel?.cancelSimulation()
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

  private func simulationContent(viewModel: SimulationViewModel) -> some View {
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

            // Thinking indicators
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
          .padding(.vertical, 8)
        }
        .onChange(of: viewModel.logEntries.count) {
          if let last = viewModel.logEntries.last {
            withAnimation {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
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
    }
  }

  // MARK: - Header

  private func headerBar(viewModel: SimulationViewModel) -> some View {
    HStack {
      if viewModel.totalRounds > 0 {
        Text("Round \(viewModel.currentRound)/\(viewModel.totalRounds)")
          .font(.subheadline.monospacedDigit())
      }

      Spacer()

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

  // MARK: - Log Entries

  @ViewBuilder
  private func logEntryView(_ entry: LogEntry, viewModel: SimulationViewModel) -> some View {
    switch entry.kind {
    case .agentOutput(let agent, let output, let phaseType):
      AgentOutputRow(
        agent: agent, output: output, phaseType: phaseType,
        showAllThoughts: viewModel.showAllThoughts,
        showDebug: viewModel.showDebugOutput
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

  @ViewBuilder
  private func speedOrExportControl(viewModel: SimulationViewModel) -> some View {
    if viewModel.isCompleted {
      Button {
        Task { await triggerExport(viewModel: viewModel) }
      } label: {
        if isExporting {
          ProgressView().frame(width: 150)
        } else {
          Label("Export", systemImage: "square.and.arrow.up")
            .font(.title3)
            .frame(width: 150)
        }
      }
      .disabled(isExporting)
    } else {
      Picker("Speed", selection: Bindable(viewModel).speed) {
        ForEach(PlaybackSpeed.allCases) { speed in
          Text(speed.label).tag(speed)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 150)
    }
  }

  private func controlBar(viewModel: SimulationViewModel) -> some View {
    HStack(spacing: 16) {
      // Pause/Resume
      Button {
        viewModel.isPaused.toggle()
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

      // Debug toggle
      Button {
        viewModel.showDebugOutput.toggle()
      } label: {
        Image(systemName: viewModel.showDebugOutput ? "ladybug.fill" : "ladybug")
          .font(.title3)
          .foregroundStyle(viewModel.showDebugOutput ? .orange : .secondary)
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
        scenarioRepository: deps.scenarioRepository
      )
      viewModel = simViewModel

      // Store task reference so cancelSimulation() (e.g., on memory warning) works.
      let runTask = Task {
        await simViewModel.run(scenario: parsed, llm: deps.llmService)
      }
      simViewModel.runTask = runTask
      await runTask.value
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
