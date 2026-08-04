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
  @State var turns: [TurnRecord] = []  // not private — read by +Export sibling
  @State var events: [CodePhaseEventRecord] = []  // not private — read by +Export sibling
  @State private var items: [ResultDetailTimelineBuilder.Item] = []
  @State var simulation: SimulationRecord?  // not private — see note above
  @State var scenario: ScenarioRecord?  // not private — see note above
  /// Agent names in scenario-declared order, used to drive position-
  /// based avatar color assignment on turn rows. Empty when the
  /// scenario YAML couldn't be decoded (legacy data, YAML drift); in
  /// that case `AgentOutputRow` falls back to name-based avatar
  /// resolution.
  @State var agentOrder: [String] = []  // not private — see note above
  /// Personas in scenario-declared order, decoded from the run's scenario
  /// snapshot alongside ``agentOrder``. Drives the tap-to-view-persona sheet
  /// (#942). Empty for runs whose scenario YAML couldn't be decoded (pre-v7
  /// deleted scenario, YAML drift) — in that case the turn rows stay
  /// non-tappable (``turnRow`` passes `onAvatarTap: nil`).
  @State var personas: [Persona] = []  // not private — see note above
  /// The persona shown when the user taps an agent's avatar / name (#942).
  @State var selectedPersona: PersonaSheetItem?  // not private — see note above
  /// Ids of declaration turns to decorate with the 🃏 contradiction badge
  /// (#916), recomputed off-main at load from the persisted records. Empty
  /// for pre-#916 runs (no `declared_intent` fields) and for runs whose
  /// scenario snapshot couldn't be parsed (no choose options to compare
  /// against) — both degrade to an unbadged timeline.
  @State var contradictionBadgedTurnIDs: Set<String> = []  // not private — see note above
  @State private var isLoading = true
  /// Cached D8 resume gate (resolved once in `loadData` via resolveIsResumable)
  /// so the banner never re-decodes `stateJSON` per `body`. Not `private` —
  /// the `+ResumeBanner` sibling reads it.
  @State var isResumable = false
  @State var showAllThoughts = true  // not private — see note above
  // Export state — not private: written by the `+Export.swift` sibling's
  // `triggerExport` / `triggerYAMLExport` (sibling extensions can't see private).
  @State var exportPayload: ResultMarkdownExporter.ExportedResult?
  @State var isExporting = false
  @State var exportError: String?
  @State var yamlExportPayload: YAMLReplayExporter.ExportedResult?
  @State var isExportingYAML = false
  @State var yamlExportError: String?
  @State var isShowingDeleteConfirm = false  // not private — see note above
  @State var deleteError: String?  // not private — see note above
  /// Final scoreboard for a run with rankable scores, decoded once from the
  /// persisted `SimulationState` in `loadData` (see `resolveScoreboard`) so the
  /// toolbar gate + sheet never re-decode `stateJSON` per `body`. `nil` for a
  /// vote-only / score-empty run — the scoreboard affordance stays hidden
  /// (parity with the live `SimulationView` card gate).
  @State var scoreboard: ScoreboardSnapshot?  // not private — read by +Scoreboard sibling
  @State var showScoreboard = false  // not private — set by +Scoreboard sibling's toolbar item

  // Per-view filter for code-phase row rendering. Mirrors the exporter's
  // whole-string Markdown sweep (`ResultMarkdownExporter.export` filters the
  // rendered output) so view and export agree on what the user sees.
  // ContentFilter is `nonisolated Sendable` and effectively immutable, so a
  // per-view instance is cheap.
  let contentFilter = ContentFilter()
  // Non-private + explicit colorScheme: the `+Share.swift` sibling composes and
  // presents these (ImageRenderer ignores ambient appearance). (#1070)
  @State var highlightShareItem: HighlightShareItem?
  // Custom story-share sheet context (#1083); +Share.swift composes it.
  @State var highlightShareContext: HighlightShareContext?
  @Environment(\.colorScheme) var colorScheme

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
    // Pin the frame before the ground: `.background` sizes to the primary view,
    // so without this the ground's extent depends on whether each arm happens to
    // be greedy — `ProgressView` is not. Pinned, it does not. `SimulationView`
    // carries the same pair for the same reason.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.screenBackground.ignoresSafeArea())
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
      // Scoreboard affordance — parity with the live SimulationView control-bar
      // button. Gated on a rankable score so a vote-only run shows no button
      // (see resolveScoreboard / +Scoreboard sibling).
      scoreboardToolbarItem
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
          // Demo-replay YAML export is a curator/authoring tool — the
          // output can only be replayed by bundling it into
          // `Resources/DemoReplays/` (there's no user-facing replay path),
          // so it's gated to DEBUG builds and hidden from TestFlight users.
          // The "Developer" section header marks it as a dev-only action
          // without a verbose per-item label prefix.
          #if DEBUG
            Section(String(localized: "Developer")) {
              Button {
                Task { await triggerYAMLExport() }
              } label: {
                Label(String(localized: "Export for demo replay"), systemImage: "film")
              }
              .disabled(!canExportYAML)
              // ADR-021 D8 QA hook — see forceFailedForQA in +ResumeBanner.
              Button {
                Task { await forceFailedForQA() }
              } label: {
                Label(
                  String(localized: "Force .failed (D8 resume QA)"),
                  systemImage: "exclamationmark.octagon")
              }
              .disabled(simulation == nil)
            }
          #endif
          Divider()
          Button(role: .destructive) {
            isShowingDeleteConfirm = true
          } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
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
    .sheet(item: $selectedPersona) { item in
      PersonaDetailSheet(persona: item.persona, position: item.position)
    }
    .highlightShareSurfaces(item: $highlightShareItem, context: $highlightShareContext)
    .sheet(isPresented: $showScoreboard) {
      // `showScoreboard` is only reachable via the gated toolbar button, which
      // is present only when `scoreboard != nil` — the `?? [:]` is a defensive
      // fallback, never hit in practice.
      ScoreboardSheet(
        scores: scoreboard?.scores ?? [:],
        eliminated: scoreboard?.eliminated ?? [:]
      )
      .presentationDetents([.medium])
      .deepLinkGated()
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
        // Failed-run resume affordance (ADR-021 D8) — a `.failed` run holding a
        // valid round checkpoint offers "resume from round N+1". Mutually
        // exclusive with the DegradedRunBadge below (`.failed` vs `.completed`).
        resumeBanner
        // Degraded-run annotation (ADR-021 D6) — a muted summary banner when
        // this completed run omitted one or more LLM turns. Gated to
        // completed + count > 0 by `DegradedRunBadge`.
        if let skipped = DegradedRunBadge.skippedTurnCount(
          status: simulation?.simulationStatus,
          degradedTurnCount: simulation?.degradedTurnCount ?? 0) {
          Label(
            String(format: String(localized: "Turns skipped ×%lld"), skipped),
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(Color.muted)
          .accessibilityIdentifier("resultDetail.degradedBadge")
        }
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

  // turnRow / personaItem / decodeTurnOutput live in
  // ResultDetailView+TurnRows.swift (file_length split). The @State they
  // read is internal (not private) for the same reason as `simulation`.

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
    /// Personas in scenario-declared order (parallel to ``agentOrder``),
    /// decoded from the same parse. Empty on decode failure — drives the
    /// tap-to-view-persona degrade (#942).
    let personas: [Persona]
    /// Declaration-turn ids to decorate with the 🃏 badge (#916), computed
    /// off-main from the fetched turns + the snapshot's choose options.
    let contradictionBadgedTurnIDs: Set<String>
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
        let personas: [Persona]
        let chooseOptions: [String]
        if let scenarioRecord = scenario,
          let parsed = try? ScenarioLoader().load(yaml: scenarioRecord.yamlDefinition) {
          agentOrder = parsed.personas.map(\.name)
          personas = parsed.personas
          chooseOptions = ContradictionDetectionLogic.chooseOptions(in: parsed.phases)
        } else {
          agentOrder = []
          personas = []
          chooseOptions = []
        }
        return LoadedData(
          turns: turns, events: events, items: items,
          simulation: sim, scenario: scenario, agentOrder: agentOrder,
          personas: personas,
          contradictionBadgedTurnIDs: ResultDetailTimelineBuilder.contradictionBadgedTurnIDs(
            turns: turns, options: chooseOptions))
      }
      apply(fetched)
    } catch {
      self.turns = []
      self.events = []
      self.items = []
      self.isResumable = false
      self.scoreboard = nil
    }
    self.isLoading = false
  }

  /// Applies a successful load to view state, including the load-once gates —
  /// the ADR-021 D8 resume banner (``resolveIsResumable(_:)``) and the final
  /// scoreboard (``resolveScoreboard(_:)``) — each a single main-thread decode
  /// cached here so `body` never re-decodes `stateJSON`.
  private func apply(_ fetched: LoadedData) {
    self.turns = fetched.turns
    self.events = fetched.events
    self.items = fetched.items
    self.simulation = fetched.simulation
    self.scenario = fetched.scenario
    self.agentOrder = fetched.agentOrder
    self.personas = fetched.personas
    self.contradictionBadgedTurnIDs = fetched.contradictionBadgedTurnIDs
    self.isResumable = resolveIsResumable(fetched.simulation)
    self.scoreboard = resolveScoreboard(fetched.simulation)
  }
}
