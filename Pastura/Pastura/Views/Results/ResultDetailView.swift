import SwiftUI
import UIKit

/// Replays a past simulation by displaying its turn records and code-phase
/// events as a read-only timeline.
///
/// Both `TurnRecord` and `CodePhaseEventRecord` are loaded once on appear,
/// merged by `sequenceNumber` via `ResultDetailTimelineBuilder`, and the
/// result is cached in `@State` to avoid re-decoding `CodePhaseEventPayload`
/// JSON on every body re-render (e.g. when `showAllThoughts` toggles).
struct ResultDetailView: View {  // swiftlint:disable:this type_body_length
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
  @State private var yamlExportPayload: YAMLReplayExporter.ExportedResult?
  @State private var isExportingYAML = false
  @State private var yamlExportError: String?

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

  /// Gate for the "Export for demo" YAML button. Same completion
  /// requirement as the Markdown export — a paused or running
  /// simulation would produce a truncated replay that misrepresents
  /// the result.
  private var canExportYAML: Bool {
    !isExportingYAML && simulation?.simulationStatus == .completed
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
      ToolbarItem(placement: .primaryAction) {
        // Sits next to the Markdown share button so the two export
        // paths are equally discoverable. Keeping it in
        // `.secondaryAction` would bury it in the overflow menu and
        // would simultaneously push the thoughts toggle into the
        // overflow too (SwiftUI promotes secondary items to an
        // overflow button once more than one is present).
        Button {
          Task { await triggerYAMLExport() }
        } label: {
          if isExportingYAML {
            ProgressView()
          } else {
            Image(systemName: "film")
          }
        }
        .disabled(!canExportYAML)
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          showAllThoughts.toggle()
        } label: {
          Image(systemName: showAllThoughts ? "text.bubble.fill" : "text.bubble")
            .foregroundStyle(showAllThoughts ? Color.moss : Color.inkSecondary)
        }
      }
    }
    .sheet(item: $exportPayload) { payload in
      ShareSheet(activityItems: [payload.text, payload.fileURL])
    }
    .sheet(item: $yamlExportPayload) { payload in
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
    .alert(
      "Replay export failed",
      isPresented: Binding(
        get: { yamlExportError != nil },
        set: { if !$0 { yamlExportError = nil } }
      )
    ) {
      Button("OK", role: .cancel) { yamlExportError = nil }
    } message: {
      Text(yamlExportError ?? "")
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
            subPhaseWrapper(item: item) { turnRow(turn) }
          case .codePhase(_, let payload):
            subPhaseWrapper(item: item) { codePhaseRow(payload) }
          }
        }
      }
      .padding(.vertical, 8)
    }
  }

  /// Wraps a row with a leading indent and "↳ sub-phase" caption when the
  /// item's `phasePath` depth is greater than 1 (i.e. it lives inside a
  /// conditional branch). Top-level items (depth ≤ 1) pass through unchanged.
  @ViewBuilder
  private func subPhaseWrapper<Content: View>(
    item: ResultDetailTimelineBuilder.Item,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if (item.phasePath?.count ?? 0) > 1 {
      VStack(alignment: .leading, spacing: 2) {
        Text("↳ sub-phase")
          .textStyle(Typography.tagPhase)
          .foregroundStyle(Color.muted)
          .padding(.leading, 32)
        content()
          .padding(.leading, 16)
      }
    } else {
      content()
    }
  }

  private func roundSeparator(_ round: Int) -> some View {
    HStack {
      Rectangle().fill(Color.rule).frame(height: 1)
      Text("Round \(round)")
        .textStyle(Typography.tagPhase)
        .foregroundStyle(Color.inkSecondary)
      Rectangle().fill(Color.rule).frame(height: 1)
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
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.inkSecondary)
        Text("Round \(turn.roundNumber)")
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.inkSecondary)
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
      contentFilter: contentFilter,
      environment: env)
    let state = decodeState(from: simulation) ?? SimulationState()
    let input = ResultDetailExportAssembler.assemble(
      simulation: simulation, scenario: scenario,
      turns: turns, events: events, state: state)

    do {
      let result = try exporter.export(input)
      self.exportPayload = result
    } catch {
      self.exportError = error.localizedDescription
    }
  }

  private func decodeState(from record: SimulationRecord) -> SimulationState? {
    guard let data = record.stateJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SimulationState.self, from: data)
  }

  /// Runs the demo-replay YAML exporter and hands the result to a
  /// separate Share Sheet. Parallel to ``triggerExport`` (Markdown)
  /// but emits `docs/specs/demo-replay-spec.md` §3.2 schema for
  /// curator ingestion into `Resources/DemoReplays/`.
  private func triggerYAMLExport() async {
    guard let simulation, let scenario else { return }
    isExportingYAML = true
    defer { isExportingYAML = false }

    let exporter = YAMLReplayExporter(contentFilter: contentFilter)
    let input = YAMLReplayExporter.Input(
      simulation: simulation, scenario: scenario,
      turns: turns, codePhaseEvents: events)

    do {
      let result = try exporter.export(input)
      self.yamlExportPayload = result
    } catch {
      self.yamlExportError = error.localizedDescription
    }
  }
}
