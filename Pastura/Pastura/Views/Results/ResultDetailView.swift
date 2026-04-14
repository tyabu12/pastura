import SwiftUI
import UIKit

/// Replays a past simulation by displaying its turn records as a read-only log.
struct ResultDetailView: View {
  let simulationId: String

  @Environment(AppDependencies.self) private var dependencies
  @State private var turns: [TurnRecord] = []
  @State private var simulation: SimulationRecord?
  @State private var scenario: ScenarioRecord?
  @State private var isLoading = true
  @State private var showDebug = false
  @State private var showAllThoughts = false
  @State private var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State private var isExporting = false
  @State private var exportError: String?

  private var canExport: Bool {
    !isExporting && simulation?.simulationStatus == .completed
      && scenario != nil
  }

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading...")
      } else if turns.isEmpty {
        ContentUnavailableView(
          "No Data",
          systemImage: "tray",
          description: Text("No turn records found for this simulation")
        )
      } else {
        turnLog
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
          showDebug.toggle()
        } label: {
          Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
            .foregroundStyle(showDebug ? .orange : .secondary)
        }
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

  /// Builds a flat list of display items with round separators inserted.
  private var displayItems: [DisplayItem] {
    var items: [DisplayItem] = []
    var lastRound = 0
    for turn in turns {
      if turn.roundNumber != lastRound {
        lastRound = turn.roundNumber
        items.append(.roundSeparator(round: turn.roundNumber))
      }
      items.append(.turn(turn))
    }
    return items
  }

  private enum DisplayItem: Identifiable {
    case roundSeparator(round: Int)
    case turn(TurnRecord)

    var id: String {
      switch self {
      case .roundSeparator(let round): "sep-\(round)"
      case .turn(let record): record.id
      }
    }
  }

  private var turnLog: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        ForEach(displayItems) { item in
          switch item {
          case .roundSeparator(let round):
            HStack {
              Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
              Text("Round \(round)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
              Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

          case .turn(let turn):
            turnRow(turn)
          }
        }
      }
      .padding(.vertical, 8)
    }
  }

  @ViewBuilder
  private func turnRow(_ turn: TurnRecord) -> some View {
    if let agentName = turn.agentName, let phaseType = PhaseType(rawValue: turn.phaseType) {
      let output = decodeTurnOutput(turn)
      AgentOutputRow(
        agent: agentName,
        output: output,
        phaseType: phaseType,
        showAllThoughts: showAllThoughts,
        showDebug: showDebug
      )
      .padding(.horizontal)
    } else {
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
  private struct LoadedData: Sendable {
    let turns: [TurnRecord]
    let simulation: SimulationRecord?
    let scenario: ScenarioRecord?
  }

  private func loadData() async {
    let turnRepo = dependencies.turnRepository
    let simRepo = dependencies.simulationRepository
    let scenarioRepo = dependencies.scenarioRepository
    let simId = simulationId
    do {
      let fetched: LoadedData = try await offMain {
        let sim = try simRepo.fetchById(simId)
        let scenario = try sim.flatMap { try scenarioRepo.fetchById($0.scenarioId) }
        let turns = try turnRepo.fetchBySimulationId(simId)
        return LoadedData(turns: turns, simulation: sim, scenario: scenario)
      }
      self.turns = fetched.turns
      self.simulation = fetched.simulation
      self.scenario = fetched.scenario
    } catch {
      self.turns = []
    }
    self.isLoading = false
  }

  private func triggerExport() async {
    guard let simulation, let scenario else { return }
    isExporting = true
    defer { isExporting = false }

    let env = ResultMarkdownExporter.ExportEnvironment(
      deviceModel: UIDevice.current.model,
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
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
