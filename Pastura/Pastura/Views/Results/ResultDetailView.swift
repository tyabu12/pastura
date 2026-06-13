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

  // Not `private`: read by the `+Delete.swift` sibling extension, which
  // can't see `private` members (visible only to same-file extensions).
  @Environment(AppDependencies.self) var dependencies
  // Used to pop back to the results list after this run is deleted.
  @Environment(AppRouter.self) var router
  @State private var turns: [TurnRecord] = []
  @State private var events: [CodePhaseEventRecord] = []
  @State private var items: [ResultDetailTimelineBuilder.Item] = []
  @State var simulation: SimulationRecord?  // not private — see note above
  @State private var scenario: ScenarioRecord?
  /// Agent names in scenario-declared order, used to drive position-
  /// based avatar color assignment on turn rows. Empty when the
  /// scenario YAML couldn't be decoded (legacy data, YAML drift); in
  /// that case `AgentOutputRow` falls back to name-based avatar
  /// resolution.
  @State private var agentOrder: [String] = []
  @State private var isLoading = true
  @State private var showAllThoughts = true
  @State private var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State private var isExporting = false
  @State private var exportError: String?
  @State private var yamlExportPayload: YAMLReplayExporter.ExportedResult?
  @State private var isExportingYAML = false
  @State private var yamlExportError: String?
  @State var isShowingDeleteConfirm = false  // not private — see note above
  @State var deleteError: String?  // not private — see note above

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
        ProgressView(String(localized: "Loading..."))
      } else if items.isEmpty {
        ContentUnavailableView(
          String(localized: "No Data"),
          systemImage: "tray",
          description: Text(String(localized: "No turn records found for this simulation"))
        )
      } else {
        timelineLog
      }
    }
    .navigationTitle(String(localized: "Result Detail"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
      // The eye toggle stays a direct icon so its ON/OFF state reads at a
      // glance (a menu row can't show that). Moved from `.secondaryAction`
      // to `.primaryAction` so it no longer collapses into an automatic
      // overflow that fought with the action menu below.
      ToolbarItem(placement: .primaryAction) {
        ThoughtVisibilityToggle(isOn: $showAllThoughts)
      }
      .hidingPasturaSharedBackground()
      // Export (Markdown / demo replay) + delete consolidated into one
      // overflow Menu: the two icon-only export buttons were
      // indistinguishable at a glance, and the crowded trailing cluster
      // truncated the inline title (e.g. ja "結果の詳細" → "結果の…").
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button {
            Task { await triggerExport() }
          } label: {
            Label(String(localized: "Export as Markdown"), systemImage: "doc.text")
          }
          .disabled(!canExport)
          Button {
            Task { await triggerYAMLExport() }
          } label: {
            Label(String(localized: "Export for demo replay"), systemImage: "film")
          }
          .disabled(!canExportYAML)
          Divider()
          Button(role: .destructive) {
            isShowingDeleteConfirm = true
          } label: {
            Label(String(localized: "Delete this run"), systemImage: "trash")
          }
          .disabled(!canDelete)
          .accessibilityIdentifier("resultDetail.deleteButton")
        } label: {
          // Spinner while an export is preparing — the menu has closed
          // by then, so this is the only in-flight affordance.
          if isExporting || isExportingYAML {
            ProgressView()
          } else {
            Image(systemName: "ellipsis.circle")
          }
        }
        .accessibilityIdentifier("resultDetail.actionsMenu")
      }
      .hidingPasturaSharedBackground()
    }
    .sheet(item: $exportPayload) { payload in
      ShareSheet(activityItems: [payload.text, payload.fileURL])
    }
    .sheet(item: $yamlExportPayload) { payload in
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
    .alert(
      String(localized: "Replay export failed"),
      isPresented: Binding(
        get: { yamlExportError != nil },
        set: { if !$0 { yamlExportError = nil } }
      )
    ) {
      Button(String(localized: "OK"), role: .cancel) { yamlExportError = nil }
    } message: {
      Text(yamlExportError ?? "")
    }
    .modifier(
      ResultDeleteConfirmationModifier(
        isPresented: $isShowingDeleteConfirm,
        deleteError: $deleteError,
        onConfirm: { await deleteThisRun() }
      )
    )
    .task {
      await loadData()
    }
  }

  private var timelineLog: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: ChatBubbleLayout.bubbleSpacing) {
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
      // Container-level horizontal padding (20pt, matching Demo
      // strategy) replaces the per-row `.padding(.horizontal)` on
      // `roundSeparator` / `turnRow` / legacy fallback. See #273
      // PR 2 — chat-stream token alignment across Demo / Sim / Results.
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
    }
    // Post-load anchor: only rendered once timeline items resolve, so
    // ScreenshotTourTests can wait on it instead of sleeping.
    .accessibilityIdentifier("resultDetail.timeline")
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
        // `metaLabel` (9pt semibold mono, mixed case) — `tagPhase`
        // would force "↳ SUB-PHASE" UPPER which reads shouty for a
        // prose-like marker. tagPhase stays for one-word phase tags
        // (WORD WOLF). See design-system §3.2.
        Text(String(localized: "↳ sub-phase"))
          .textStyle(Typography.metaLabel)
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
      // `metaLabel` keeps "Round N" mixed case — tagPhase would
      // upper-case to "ROUND N" which reads shouty for a prose
      // marker. tagPhase stays reserved for one-word phase tags
      // (WORD WOLF). See design-system §3.2.
      Text(String(format: String(localized: "Round %lld"), round))
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
      Rectangle().fill(Color.rule).frame(height: 1)
    }
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
        showAllThoughts: showAllThoughts,
        agentPosition: agentOrder.firstIndex(of: agentName)
      )
    } else {
      // Pre-#92 fallback: TurnRecord without agentName. Newer code phases
      // emit CodePhaseEventRecord rows instead, so this path is only hit
      // by legacy data.
      HStack(spacing: 4) {
        Text(turn.phaseType)
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.inkSecondary)
        Text(String(format: String(localized: "Round %lld"), turn.roundNumber))
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.inkSecondary)
      }
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
    /// Agent names in scenario-declared order. Decoded once off-main
    /// alongside the record fetch so position-priority avatar lookup
    /// on every turn row is an O(1) cache hit. Empty when YAML decode
    /// fails — turnRow falls back to name-based avatar resolution.
    let agentOrder: [String]
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
        // Resolve via the run's snapshot (faithful to what ran; survives
        // scenario edit/delete), falling back to the live scenario only for
        // pre-v7 runs. Feeds both this detail view's agent ordering and the
        // export path (which reads `self.scenario`).
        let scenario = try sim.flatMap {
          try ScenarioSnapshotResolver.resolve(for: $0, liveLookup: scenarioRepo.fetchById)
        }
        let turns = try turnRepo.fetchBySimulationId(simId)
        let events = try eventRepo.fetchBySimulationId(simId)
        let items = ResultDetailTimelineBuilder.build(turns: turns, events: events)
        // `try?` silently discards a YAML drift / malformed record and
        // falls back to empty — callers handle empty agentOrder by
        // skipping position-based avatar resolution. Acceptable
        // degradation: past results with unparseable scenarios still
        // render, just with name-based avatars.
        let agentOrder: [String]
        if let scenarioRecord = scenario,
          let parsed = try? ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition) {
          agentOrder = parsed.personas.map(\.name)
        } else {
          agentOrder = []
        }
        return LoadedData(
          turns: turns, events: events, items: items,
          simulation: sim, scenario: scenario, agentOrder: agentOrder)
      }
      self.turns = fetched.turns
      self.events = fetched.events
      self.items = fetched.items
      self.simulation = fetched.simulation
      self.scenario = fetched.scenario
      self.agentOrder = fetched.agentOrder
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
