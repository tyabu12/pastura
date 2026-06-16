import SwiftUI

/// The main screen displaying all scenarios grouped by presets and user-created.
struct HomeView: View {
  @Environment(AppDependencies.self) private var dependencies
  @Environment(AppRouter.self) private var router
  // Drives the row description's line limit: 1 truncated line at normal
  // sizes (d3), unlimited wrap at accessibility sizes (HomeScenarioRowFormat).
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: HomeViewModel?
  @State private var pendingDeletion: PendingScenarioDeletion?

  /// A user-scenario deletion awaiting confirmation. Carries the target ids
  /// (an `.onDelete` swipe is normally one, but multi-select can batch) and
  /// the first scenario's name for the confirmation copy.
  private struct PendingScenarioDeletion: Identifiable {
    let ids: [String]
    let name: String
    var id: String { ids.joined(separator: ",") }
  }

  /// Confirmation copy for deleting a user scenario. Since v7 the scenario
  /// FK is `ON DELETE SET NULL`, so past runs are orphaned (kept), not
  /// cascade-deleted — the copy reassures the user their history survives.
  nonisolated static func scenarioDeletionMessage(name: String) -> String {
    String(
      format: String(
        localized: "“%@” will be deleted. Past simulation results are kept and stay viewable."),
      name)
  }

  var body: some View {
    // The Home tab's `NavigationStack` (and its `.navigationDestination`
    // registration via ``RouteResolver``) is owned by ``RootTabView`` so
    // every tab shares one Route universe (ADR-016 D3). This view is the
    // Home tab's root *content*; `router` (read below) is the Home tab's
    // `AppRouter`, injected per-tab by `RootTabView`.
    Group {
      if let viewModel {
        scenarioList(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // `.navigationTitle("Pastura")` is kept deliberately even though the
    // visible center is replaced by the `.principal` brand lockup below.
    // The nav bar's accessibility identity (`navigationBars["Pastura"]`,
    // asserted by NavigationRegression / EditorReload / BackGesture UI
    // tests) derives from the title string, and design-system § 5.11's
    // tab-root inline-title convention is satisfied by it. A `.principal`
    // item replaces the title *visual* without clearing the underlying
    // `UINavigationItem.title`, so both stay true at once.
    .navigationTitle("Pastura")
    .navigationBarTitleDisplayMode(.inline)
    // Hide the bar's backing material so the brand lockup reads against the
    // cream screen background (d3 design). This removes the bar material but
    // NOT the iOS 26 per-item Liquid Glass capsule — that needs the separate
    // `.hidingPasturaSharedBackground()` on each ToolbarItem below.
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        HStack(spacing: 9) {
          Image("BrandIcon")
            .resizable()
            .frame(width: 27, height: 27)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          // verbatim: "Pastura" is a brand name, never localized — keeps it
          // out of Localizable.xcstrings and past the i18n SwiftLint tripwire.
          Text(verbatim: "Pastura")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Color.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.brandWordmark")
      }
      .hidingPasturaSharedBackground()
      ToolbarItem(placement: .primaryAction) {
        NavigationLink(value: newScenarioRoute()) {
          Label(String(localized: "New Scenario"), systemImage: "plus")
        }
        .accessibilityIdentifier("home.newScenarioButton")
      }
      .hidingPasturaSharedBackground()
    }
    .task {
      // Defer assignment until both `loadScenarios()` and
      // `refreshGalleryUpdateBadges()` complete so gallery update badges
      // appear together with the row that owns them — otherwise the list
      // shows first and badges pop in a frame later. Guard prevents
      // re-creation under `.task` re-fire.
      guard viewModel == nil else { return }
      let newViewModel = HomeViewModel(
        repository: dependencies.scenarioRepository,
        simulationRepository: dependencies.simulationRepository)
      await newViewModel.loadScenarios()
      await newViewModel.refreshGalleryUpdateBadges(using: dependencies.galleryService)
      viewModel = newViewModel
    }
    // Refresh the list whenever the user navigates back to root.
    // `.task` only runs on initial mount; pushed views like the editor
    // don't re-trigger it on dismiss. D5.3: `router` is the Home tab's
    // `AppRouter` (per-tab injected), so this pop-reload stays Home-local.
    .onChange(of: router.path.count) { oldCount, newCount in
      if newCount < oldCount {
        Task {
          await viewModel?.loadScenarios()
          await viewModel?.refreshGalleryUpdateBadges(using: dependencies.galleryService)
        }
      }
    }
  }

  @ViewBuilder
  private func scenarioList(viewModel: HomeViewModel) -> some View {
    List {
      if !viewModel.presets.isEmpty {
        Section(String(localized: "Presets")) {
          ForEach(viewModel.presets, id: \.id) { scenario in
            scenarioRow(scenario, metadata: viewModel.rowMetadata[scenario.id])
              .pasturaCardRow()
          }
        }
      }

      userScenariosSection(viewModel: viewModel)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .confirmationDialog(
      String(localized: "Delete Scenario?"),
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { presented in if !presented { pendingDeletion = nil } }),
      presenting: pendingDeletion
    ) { pending in
      deleteConfirmationActions(pending, viewModel: viewModel)
    } message: { pending in
      Text(Self.scenarioDeletionMessage(name: pending.name))
    }
    .refreshable {
      await viewModel.loadScenarios()
      await viewModel.refreshGalleryUpdateBadges(using: dependencies.galleryService)
    }
    .overlay {
      if let error = viewModel.errorMessage {
        ContentUnavailableView(
          String(localized: "Error"),
          systemImage: "exclamationmark.triangle",
          description: Text(error)
        )
      }
    }
  }

  @ViewBuilder
  private func userScenariosSection(viewModel: HomeViewModel) -> some View {
    Section(String(localized: "My Scenarios")) {
      if viewModel.userScenarios.isEmpty {
        ContentUnavailableView(
          String(localized: "No Scenarios"),
          systemImage: "doc.text",
          description: Text(String(localized: "Tap + to import a YAML scenario"))
        )
      } else {
        ForEach(viewModel.userScenarios, id: \.id) { scenario in
          scenarioRow(
            scenario,
            metadata: viewModel.rowMetadata[scenario.id],
            hasGalleryUpdate: viewModel.galleryUpdateBadges.contains(scenario.id)
          )
          .pasturaCardRow()
        }
        .onDelete { offsets in
          // Confirm before deleting — destructive and not obviously
          // recoverable from the user's point of view. Past results survive
          // (orphaned), but the scenario itself is gone.
          // My Scenarios has no EditButton/multi-select, so a swipe deletes a
          // single row — naming the first scenario in the copy is accurate.
          let scenarios = offsets.map { viewModel.userScenarios[$0] }
          pendingDeletion = PendingScenarioDeletion(
            ids: scenarios.map(\.id),
            name: scenarios.first?.name ?? "")
        }
      }
    }
  }

  @ViewBuilder
  private func deleteConfirmationActions(
    _ pending: PendingScenarioDeletion, viewModel: HomeViewModel
  ) -> some View {
    Button(role: .destructive) {
      Task {
        for id in pending.ids {
          await viewModel.deleteScenario(id)
        }
        pendingDeletion = nil
      }
    } label: {
      Text(String(localized: "Delete"))
    }
    Button(role: .cancel) {
      pendingDeletion = nil
    } label: {
      Text(String(localized: "Cancel"))
    }
  }

  private func scenarioRow(
    _ scenario: ScenarioRecord,
    metadata: ScenarioRowMetadata?,
    hasGalleryUpdate: Bool = false
  ) -> some View {
    // initialName supplies the scenario name to navigationTitle from
    // the first frame of the push, before ScenarioDetailViewModel
    // finishes loading. Identity-neutral via RouteHint (ADR-008).
    NavigationLink(
      value: Route.scenarioDetail(
        scenarioId: scenario.id,
        initialName: .init(scenario.name)
      )
    ) {
      scenarioRowLabel(scenario, metadata: metadata, hasGalleryUpdate: hasGalleryUpdate)
    }
    .accessibilityIdentifier("home.scenarioListCell.\(scenario.id)")
  }

  private func scenarioRowLabel(
    _ scenario: ScenarioRecord,
    metadata: ScenarioRowMetadata?,
    hasGalleryUpdate: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 6) {
        Text(scenario.name)
          .font(.headline)
          .foregroundStyle(Color.ink)
        // Preset badge moves inline next to the name (d3) rather than its
        // own caption row below.
        if scenario.isPreset {
          Text(String(localized: "Preset"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: Capsule())
        }
        if hasGalleryUpdate {
          Text(String(localized: "Update"))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.2), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
      }
      if HomeScenarioRowFormat.showsMetaLine(
        agentCount: metadata?.agentCount, rounds: metadata?.rounds) {
        scenarioMetaLine(metadata: metadata)
      }
      if let description = metadata?.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(
            HomeScenarioRowFormat.descriptionLineLimit(
              isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
          )
          .truncationMode(.tail)
      }
    }
    .padding(.vertical, 4)
  }

  /// Row meta line — one sheep avatar per agent (clamped via
  /// ``HomeScenarioRowFormat/maxRowSheep``) followed by the round count. The
  /// sheep are decorative (``SheepAvatar`` is `.accessibilityHidden`); the
  /// true agent count is surfaced to VoiceOver through the group's
  /// `%lld agents` label so the visual clamp never hides it.
  @ViewBuilder
  private func scenarioMetaLine(metadata: ScenarioRowMetadata?) -> some View {
    let sheepCount = HomeScenarioRowFormat.rowSheepCount(agentCount: metadata?.agentCount)
    HStack(spacing: 7) {
      if sheepCount > 0 {
        HStack(spacing: 2) {
          ForEach(0..<sheepCount, id: \.self) { index in
            SheepAvatar(character: .forAgent("", position: index), size: SheepAvatar.rowSize)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          String(format: String(localized: "%lld agents"), metadata?.agentCount ?? 0))
      }
      if let roundsLabel = HomeScenarioRowFormat.roundsLabel(rounds: metadata?.rounds) {
        if sheepCount > 0 {
          Text(verbatim: "·")
            .font(.caption2)
            .foregroundStyle(Color.muted)
        }
        Text(roundsLabel)
          .font(.caption)
          .foregroundStyle(Color.muted)
      }
    }
  }

}

// Toolbar route helper, split into an extension to keep the main
// `HomeView` body under SwiftLint's `type_body_length`. Root-stack route
// resolution itself was hoisted to ``RouteResolver`` (ADR-016 D3) so all
// four tab stacks share one Route universe.
extension HomeView {
  /// Resolves the destination for the toolbar "New Scenario" menu item.
  ///
  /// Under `--ui-test-editor-seed-yaml`, `AppDependencies.uiTestEditorSeedYAML`
  /// carries a pre-verified template so `EditorReloadTests` can exercise
  /// the editor → save → Home reload path without typing YAML through
  /// XCUITest. Production always returns the empty editor.
  func newScenarioRoute() -> Route {
    #if DEBUG
      if let seed = dependencies.uiTestEditorSeedYAML {
        return .editor(templateYAML: seed)
      }
    #endif
    return .editor()
  }
}

extension View {
  /// Renders a `List` row as a flat ``PasturaCard``: white
  /// ``PasturaCardSurface`` (1pt `rule` border, 14pt radius, no shadow),
  /// inset vertically by half ``PasturaCardMetrics/interCardSpacing`` so
  /// adjacent rows read as separate cards, separators hidden.
  ///
  /// Home stays on `List` (for swipe-`.onDelete`); this is the List-host
  /// counterpart to the `ScrollView` ``PasturaCard`` container used on the
  /// other browse screens, sharing the same metrics so the card form
  /// matches across hosts.
  fileprivate func pasturaCardRow() -> some View {
    self
      .listRowSeparator(.hidden)
      .listRowBackground(
        PasturaCardSurface()
          .padding(.vertical, PasturaCardMetrics.interCardSpacing / 2)
      )
  }
}
