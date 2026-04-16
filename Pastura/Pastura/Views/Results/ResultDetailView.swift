import SwiftUI
import UIKit

/// Replays a past simulation by displaying its turn records and code-phase
/// events as a read-only timeline.
///
/// Both `TurnRecord` and `CodePhaseEventRecord` are loaded once on appear,
/// merged by `sequenceNumber` via `ResultDetailTimelineBuilder`, and the
/// result is cached in `@State` to avoid re-decoding `CodePhaseEventPayload`
/// JSON on every body re-render (e.g. when `showAllThoughts` toggles).
struct ResultDetailView: View {
  let simulationId: String

  @Environment(AppDependencies.self) private var dependencies
  @State private var turns: [TurnRecord] = []
  @State private var events: [CodePhaseEventRecord] = []
  @State private var items: [ResultDetailTimelineBuilder.Item] = []
  @State private var simulation: SimulationRecord?
  @State private var scenario: ScenarioRecord?
  @State private var isLoading = true
  @State private var showAllThoughts = true
  @State private var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State private var isExporting = false
  @State private var exportError: String?

  // Per-view filter for code-phase row rendering. Mirrors the exporter's
  // whole-string Markdown sweep (`ResultMarkdownExporter.export` filters the
  // rendered output) so view and export agree on what the user sees.
  // ContentFilter is `nonisolated Sendable` and effectively immutable, so a
  // per-view instance is cheap.
  let contentFilter = ContentFilter()

  private var canExport: Bool {
    !isExporting && simulation?.simulationStatus == .completed
      && scenario != nil
  }

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading...")
      } else if items.isEmpty {
        ContentUnavailableView(
          "No Data",
          systemImage: "tray",
          description: Text("No turn records found for this simulation")
        )
      } else {
        timelineLog
      }
    }
    .navigationTitle("Result Detail")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await triggerExport() }
        } label: {
          if isExporting {
            ProgressView()
          } else {
            Image(systemName: "square.and.arrow.up")
          }
        }
        .disabled(!canExport)
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          showAllThoughts.toggle()
        } label: {
          Image(systemName: showAllThoughts ? "text.bubble.fill" : "text.bubble")
            .foregroundStyle(showAllThoughts ? .purple : .secondary)
        }
      }
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
    .task {
      await loadData()
    }
  }

  private var timelineLog: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        ForEach(items) { item in
          switch item {
          case .roundSeparator(let round):
            roundSeparator(round)
          case .turn(let turn):
            turnRow(turn)
          case .codePhase(_, let payload):
            codePhaseRow(payload)
          }
        }
      }
      .padding(.vertical, 8)
    }
  }

  private func roundSeparator(_ round: Int) -> some View {
    HStack {
      Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
      Text("Round \(round)")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func turnRow(_ turn: TurnRecord) -> some View {
    if let agentName = turn.agentName, let phaseType = PhaseType(rawValue: turn.phaseType) {
      let output = decodeTurnOutput(turn)
      AgentOutputRow(
        agent: agentName,
        output: output,
        phaseType: phaseType,
        showAllThoughts: showAllThoughts
      )
      .padding(.horizontal)
    } else {
      // Pre-#92 fallback: TurnRecord without agentName. Newer code phases
      // emit CodePhaseEventRecord rows instead, so this path is only hit
      // by legacy data.
      HStack(spacing: 4) {
        Text(turn.phaseType)
          .font(.caption.monospaced())
          .foregroundStyle(.orange)
        Text("Round \(turn.roundNumber)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
    }
  }

  private func decodeTurnOutput(_ turn: TurnRecord) -> TurnOutput {
    guard let data = turn.parsedOutputJSON.data(using: .utf8),
      let output = try? JSONDecoder().decode(TurnOutput.self, from: data)
    else {
      return TurnOutput(fields: ["raw": turn.rawOutput])
    }
    return output
  }

  /// Bundle returned from the single `offMain` DB hop — struct avoids an N-tuple.
  /// Pre-builds `items` inside the off-main task so the view never decodes
  /// `CodePhaseEventPayload` JSON on the main thread.
  private struct LoadedData: Sendable {
    let turns: [TurnRecord]
    let events: [CodePhaseEventRecord]
    let items: [ResultDetailTimelineBuilder.Item]
    let simulation: SimulationRecord?
    let scenario: ScenarioRecord?
  }

  private func loadData() async {
    let turnRepo = dependencies.turnRepository
    let eventRepo = dependencies.codePhaseEventRepository
    let simRepo = dependencies.simulationRepository
    let scenarioRepo = dependencies.scenarioRepository
    let simId = simulationId
    do {
      let fetched: LoadedData = try await offMain {
        let sim = try simRepo.fetchById(simId)
        let scenario = try sim.flatMap { try scenarioRepo.fetchById($0.scenarioId) }
        let turns = try turnRepo.fetchBySimulationId(simId)
        let events = try eventRepo.fetchBySimulationId(simId)
        let items = ResultDetailTimelineBuilder.build(turns: turns, events: events)
        return LoadedData(
          turns: turns, events: events, items: items,
          simulation: sim, scenario: scenario)
      }
      self.turns = fetched.turns
      self.events = fetched.events
      self.items = fetched.items
      self.simulation = fetched.simulation
      self.scenario = fetched.scenario
    } catch {
      self.turns = []
      self.events = []
      self.items = []
    }
    self.isLoading = false
  }

  private func triggerExport() async {
    guard let simulation, let scenario else { return }
    isExporting = true
    defer { isExporting = false }

    let env = ResultMarkdownExporter.ExportEnvironment(
      deviceModel: UIDevice.current.model,
      osVersion: ResultMarkdownExporter.ExportEnvironment.normalizeOSVersion(
        ProcessInfo.processInfo.operatingSystemVersionString))
    let exporter = ResultMarkdownExporter(
      contentFilter: ContentFilter(),
      environment: env)
    let state = decodeState(from: simulation) ?? SimulationState()

    do {
      let result = try exporter.export(
        ResultMarkdownExporter.Input(
          simulation: simulation, scenario: scenario,
          turns: turns, state: state))
      self.exportPayload = result
    } catch {
      self.exportError = error.localizedDescription
    }
  }

  private func decodeState(from record: SimulationRecord) -> SimulationState? {
    guard let data = record.stateJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SimulationState.self, from: data)
  }
}
