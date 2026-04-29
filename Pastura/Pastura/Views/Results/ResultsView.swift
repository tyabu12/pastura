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
          ProgressView(String(localized: "Loading..."))
        } else if viewModel.groups.isEmpty {
          ContentUnavailableView(
            String(localized: "No Results"),
            systemImage: "tray",
            description: Text(String(localized: "Run a simulation to see results here"))
          )
        } else {
          resultsList(viewModel: viewModel)
        }
      } else {
        ProgressView()
      }
    }
    .navigationTitle(String(localized: "Past Results"))
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
              .textStyle(Typography.metaValue)
              .foregroundStyle(Color.muted)
          }
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func statusBadge(_ status: String) -> some View {
    // Pastura tokens (§2.3): completed = moss-dark（ステータスラベル用途、§2.3
    // で "ステータスラベル（Completed 等）" と enumerate）、paused / default
    // は ink-secondary / muted の neutral。`.green / .orange / .secondary`
    // は §1 飽和色禁則・パレット非準拠で置換。SimulationView ヘッダーの
    // Completed ラベルとも揃えてある。
    //
    // Label font も同時に `Typography.metaLabel` 化（隣接トークンの一貫性
    // — `.caption` だけ残ると section 内で system font / Pastura token が
    // 混在するため）。
    let (icon, color): (String, Color) =
      switch status {
      case "completed": ("checkmark.circle.fill", Color.mossDark)
      case "paused": ("pause.circle.fill", Color.inkSecondary)
      default: ("questionmark.circle", Color.muted)
      }
    return Label(status.capitalized, systemImage: icon)
      .textStyle(Typography.metaLabel)
      .foregroundStyle(color)
  }
}
