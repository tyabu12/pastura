import SwiftUI

/// The main screen displaying all scenarios grouped by presets and user-created.
struct HomeView: View {
  @Environment(AppDependencies.self) private var dependencies
  @Environment(AppRouter.self) private var router
  @State private var viewModel: HomeViewModel?

  var body: some View {
    // `@Bindable` shadow: an `@Observable` injected via `@Environment` is
    // immutable on the read side; the local `@Bindable` rebinding lets us
    // derive `$router.path` for `NavigationStack`'s path binding.
    @Bindable var router = router
    return NavigationStack(path: $router.path) {
      Group {
        if let viewModel {
          scenarioList(viewModel: viewModel)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Pastura")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink(value: Route.settings) {
            Label(String(localized: "Settings"), systemImage: "gearshape")
          }
          .accessibilityIdentifier("home.settingsButton")
        }
        ToolbarItem(placement: .primaryAction) {
          Menu {
            NavigationLink(value: newScenarioRoute()) {
              Label(String(localized: "New Scenario"), systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("home.newScenarioButton")
            NavigationLink(value: Route.importScenario()) {
              Label(String(localized: "Import YAML"), systemImage: "doc.text")
            }
          } label: {
            Label(String(localized: "Add"), systemImage: "plus")
          }
        }
      }
      .navigationDestination(for: Route.self) { route in
        routeDestination(route)
      }
    }
    .task {
      // Defer assignment until both `loadScenarios()` and
      // `refreshGalleryUpdateBadges()` complete so gallery update badges
      // appear together with the row that owns them — otherwise the list
      // shows first and badges pop in a frame later. Guard prevents
      // re-creation under `.task` re-fire.
      guard viewModel == nil else { return }
      let newViewModel = HomeViewModel(repository: dependencies.scenarioRepository)
      await newViewModel.loadScenarios()
      await newViewModel.refreshGalleryUpdateBadges(using: dependencies.galleryService)
      viewModel = newViewModel
    }
    // Refresh the list whenever the user navigates back to root.
    // `.task` only runs on initial mount; pushed views like the editor
    // don't re-trigger it on dismiss.
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
          }
        }
      }

      userScenariosSection(viewModel: viewModel)

      Section {
        NavigationLink(value: Route.shareBoard) {
          Label(String(localized: "Shared Scenarios"), systemImage: "square.grid.2x2.fill")
        }
        .accessibilityIdentifier("home.shareBoardButton")
        NavigationLink(value: Route.results(scenarioId: "")) {
          Label(String(localized: "Past Results"), systemImage: "clock.arrow.circlepath")
        }
      }
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
            scenario, hasGalleryUpdate: viewModel.galleryUpdateBadges.contains(scenario.id))
        }
        .onDelete { offsets in
          let ids = offsets.map { viewModel.userScenarios[$0].id }
          Task {
            for id in ids {
              await viewModel.deleteScenario(id)
            }
          }
        }
      }
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

  @ViewBuilder
  private func routeDestination(_ route: Route) -> some View {
    switch route {
    case .scenarioDetail(let scenarioId, let initialName):
      ScenarioDetailView(scenarioId: scenarioId, initialName: initialName.value)
    case .importScenario(let editingId):
      ImportView(editingId: editingId)
    case .editor(let editingId, let templateYAML):
      editorView(editingId: editingId, templateYAML: templateYAML)
    case .simulation(let scenarioId, let initialName):
      SimulationView(scenarioId: scenarioId, initialName: initialName.value)
    case .results(let scenarioId):
      ResultsView(scenarioId: scenarioId)
    case .resultDetail(let simulationId):
      ResultDetailView(simulationId: simulationId)
    case .shareBoard:
      ShareBoardView()
    case .galleryScenarioDetail(let scenario):
      GalleryScenarioDetailView(scenario: scenario)
    case .settings:
      SettingsView()
    }
  }

  private func editorView(editingId: String?, templateYAML: String?) -> some View {
    ScenarioEditorHost(
      repository: dependencies.scenarioRepository,
      editingId: editingId,
      templateYAML: templateYAML
    )
  }

  /// Resolves the destination for the toolbar "New Scenario" menu item.
  ///
  /// Under `--ui-test-editor-seed-yaml`, `AppDependencies.uiTestEditorSeedYAML`
  /// carries a pre-verified template so `EditorReloadTests` can exercise
  /// the editor → save → Home reload path without typing YAML through
  /// XCUITest. Production always returns the empty editor.
  private func newScenarioRoute() -> Route {
    #if DEBUG
      if let seed = dependencies.uiTestEditorSeedYAML {
        return .editor(templateYAML: seed)
      }
    #endif
    return .editor()
  }
}

/// Host view that owns a ``ScenarioEditorViewModel`` via `@State`.
///
/// Needed so the ViewModel is retained across HomeView re-renders — creating
/// it inside a factory function would produce a fresh instance each time,
/// losing editor state.
private struct ScenarioEditorHost: View {
  let repository: any ScenarioRepository
  let editingId: String?
  let templateYAML: String?

  @State private var viewModel: ScenarioEditorViewModel?

  var body: some View {
    Group {
      if let viewModel {
        ScenarioEditorView(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .task {
      guard viewModel == nil else { return }
      let newViewModel = ScenarioEditorViewModel(repository: repository)
      if let editingId {
        await newViewModel.loadForEditing(scenarioId: editingId)
      } else if let templateYAML {
        newViewModel.loadFromTemplate(yaml: templateYAML)
      }
      viewModel = newViewModel
    }
  }
}
