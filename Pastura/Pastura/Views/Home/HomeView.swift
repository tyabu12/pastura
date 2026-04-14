import SwiftUI

/// The main screen displaying all scenarios grouped by presets and user-created.
struct HomeView: View {
  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: HomeViewModel?
  @State private var navigationPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navigationPath) {
      Group {
        if let viewModel {
          scenarioList(viewModel: viewModel)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Pastura")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            NavigationLink(value: Route.editor()) {
              Label("New Scenario", systemImage: "doc.badge.plus")
            }
            NavigationLink(value: Route.importScenario()) {
              Label("Import YAML", systemImage: "doc.text")
            }
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
      }
      .navigationDestination(for: Route.self) { route in
        routeDestination(route)
      }
    }
    .task {
      viewModel = HomeViewModel(repository: dependencies.scenarioRepository)
      await viewModel?.loadScenarios()
      await viewModel?.refreshGalleryUpdateBadges(using: dependencies.galleryService)
    }
    // Refresh the list whenever the user navigates back to root.
    // `.task` only runs on initial mount; pushed views like the editor
    // don't re-trigger it on dismiss.
    .onChange(of: navigationPath.count) { oldCount, newCount in
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
        Section("Presets") {
          ForEach(viewModel.presets, id: \.id) { scenario in
            scenarioRow(scenario)
          }
        }
      }

      userScenariosSection(viewModel: viewModel)

      Section {
        NavigationLink(value: Route.shareBoard) {
          Label("Share Board", systemImage: "square.grid.2x2.fill")
        }
        NavigationLink(value: Route.results(scenarioId: "")) {
          Label("Past Results", systemImage: "clock.arrow.circlepath")
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
          "Error",
          systemImage: "exclamationmark.triangle",
          description: Text(error)
        )
      }
    }
  }

  @ViewBuilder
  private func userScenariosSection(viewModel: HomeViewModel) -> some View {
    Section("My Scenarios") {
      if viewModel.userScenarios.isEmpty {
        ContentUnavailableView(
          "No Scenarios",
          systemImage: "doc.text",
          description: Text("Tap + to import a YAML scenario")
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
    NavigationLink(value: Route.scenarioDetail(scenarioId: scenario.id)) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(scenario.name)
            .font(.headline)
          if hasGalleryUpdate {
            Text("Update")
              .font(.caption2.bold())
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.2), in: Capsule())
              .foregroundStyle(Color.accentColor)
          }
        }
        if scenario.isPreset {
          Text("Preset")
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

  @ViewBuilder
  private func routeDestination(_ route: Route) -> some View {
    switch route {
    case .scenarioDetail(let scenarioId):
      ScenarioDetailView(scenarioId: scenarioId)
    case .importScenario(let editingId):
      ImportView(editingId: editingId)
    case .editor(let editingId, let templateYAML):
      editorView(editingId: editingId, templateYAML: templateYAML)
    case .simulation(let scenarioId):
      SimulationView(scenarioId: scenarioId)
    case .results(let scenarioId):
      ResultsView(scenarioId: scenarioId)
    case .resultDetail(let simulationId):
      ResultDetailView(simulationId: simulationId)
    case .shareBoard:
      ShareBoardView()
    case .galleryScenarioDetail(let scenario):
      GalleryScenarioDetailView(scenario: scenario)
    }
  }

  private func editorView(editingId: String?, templateYAML: String?) -> some View {
    ScenarioEditorHost(
      repository: dependencies.scenarioRepository,
      editingId: editingId,
      templateYAML: templateYAML
    )
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
