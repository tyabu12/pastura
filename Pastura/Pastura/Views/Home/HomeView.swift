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
          NavigationLink(value: Route.importScenario()) {
            Label("Import", systemImage: "plus")
          }
        }
      }
      .navigationDestination(for: Route.self) { route in
        routeDestination(route)
      }
    }
    .task {
      let model = HomeViewModel(repository: dependencies.scenarioRepository)
      viewModel = model
      await model.loadScenarios()
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

      Section("My Scenarios") {
        if viewModel.userScenarios.isEmpty {
          ContentUnavailableView(
            "No Scenarios",
            systemImage: "doc.text",
            description: Text("Tap + to import a YAML scenario")
          )
        } else {
          ForEach(viewModel.userScenarios, id: \.id) { scenario in
            scenarioRow(scenario)
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

      Section {
        NavigationLink(value: Route.results(scenarioId: "")) {
          Label("Past Results", systemImage: "clock.arrow.circlepath")
        }
      }
    }
    .refreshable {
      await viewModel.loadScenarios()
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

  private func scenarioRow(_ scenario: ScenarioRecord) -> some View {
    NavigationLink(value: Route.scenarioDetail(scenarioId: scenario.id)) {
      VStack(alignment: .leading, spacing: 4) {
        Text(scenario.name)
          .font(.headline)
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
    case .simulation(let scenarioId):
      SimulationView(scenarioId: scenarioId)
    case .results(let scenarioId):
      ResultsView(scenarioId: scenarioId)
    case .resultDetail(let simulationId):
      ResultDetailView(simulationId: simulationId)
    }
  }
}
