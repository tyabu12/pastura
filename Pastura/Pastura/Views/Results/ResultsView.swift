import SwiftUI

/// Lists past simulation runs, grouped by scenario.
struct ResultsView: View {
  let scenarioId: String

  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: ResultsViewModel?

  var body: some View {
    Group {
      if let viewModel {
        if viewModel.isLoading {
          ProgressView("Loading...")
        } else if viewModel.groups.isEmpty {
          ContentUnavailableView(
            "No Results",
            systemImage: "tray",
            description: Text("Run a simulation to see results here")
          )
        } else {
          resultsList(viewModel: viewModel)
        }
      } else {
        ProgressView()
      }
    }
    .navigationTitle("Past Results")
    .task {
      viewModel = ResultsViewModel(
        scenarioRepository: dependencies.scenarioRepository,
        simulationRepository: dependencies.simulationRepository,
        turnRepository: dependencies.turnRepository
      )
      await viewModel?.load(scenarioId: scenarioId)
    }
  }

  private func resultsList(viewModel: ResultsViewModel) -> some View {
    List {
      ForEach(viewModel.groups) { group in
        Section(group.scenarioName) {
          ForEach(group.simulations, id: \.id) { simulation in
            NavigationLink(value: Route.resultDetail(simulationId: simulation.id)) {
              simulationRow(simulation, viewModel: viewModel)
            }
          }
        }
      }
    }
  }

  private func simulationRow(
    _ simulation: SimulationRecord,
    viewModel: ResultsViewModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(simulation.createdAt, style: .date)
        Text(simulation.createdAt, style: .time)
        Spacer()
        statusBadge(simulation.status)
      }
      .font(.subheadline)

      if let state = viewModel.decodeState(from: simulation) {
        let top3 = state.scores.sorted(by: { $0.value > $1.value }).prefix(3)
        HStack(spacing: 8) {
          ForEach(Array(top3), id: \.key) { name, score in
            Text("\(name) (\(score))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func statusBadge(_ status: String) -> some View {
    let (icon, color): (String, Color) =
      switch status {
      case "completed": ("checkmark.circle.fill", .green)
      case "paused": ("pause.circle.fill", .orange)
      default: ("questionmark.circle", .secondary)
      }
    return Label(status.capitalized, systemImage: icon)
      .font(.caption)
      .foregroundStyle(color)
  }
}
