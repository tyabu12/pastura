import SwiftUI

/// The main screen displaying all scenarios grouped by presets and user-created.
struct HomeView: View {
  @Environment(AppDependencies.self) private var dependencies
  @Environment(AppRouter.self) private var router
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
    .navigationTitle("Pastura")
    // Tab roots use an inline title for quiet chrome (design-system § 5.11);
    // the tab-root rule overrides the 固有名→large axis even though
    // "Pastura" is a brand name.
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
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
            scenarioRow(scenario)
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
            scenario, hasGalleryUpdate: viewModel.galleryUpdateBadges.contains(scenario.id)
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
    _ scenario: ScenarioRecord, hasGalleryUpdate: Bool = false
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
      scenarioRowLabel(scenario, hasGalleryUpdate: hasGalleryUpdate)
    }
    .accessibilityIdentifier("home.scenarioListCell.\(scenario.id)")
  }

  private func scenarioRowLabel(
    _ scenario: ScenarioRecord, hasGalleryUpdate: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(scenario.name)
          .font(.headline)
          .foregroundStyle(Color.ink)
        if hasGalleryUpdate {
          Text(String(localized: "Update"))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.2), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
      }
      if scenario.isPreset {
        Text(String(localized: "Preset"))
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.secondary.opacity(0.15), in: Capsule())
      }
    }
    .padding(.vertical, 2)
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
