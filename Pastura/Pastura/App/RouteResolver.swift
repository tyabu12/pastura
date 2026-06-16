import SwiftUI

/// Resolves a ``Route`` to its destination view — shared across all four
/// tab navigation stacks (ADR-016 D3).
///
/// Hoisted out of `HomeView` so every tab's
/// `NavigationStack(…).navigationDestination(for: Route.self)` resolves
/// the **same** Route universe: a `.scenarioDetail` / `.simulation` /
/// `.results(detail)` push originating inside the Search or History tab
/// must resolve identically to one from Home. Keeping the resolver inside
/// `HomeView` would tie the Route universe to a single tab's stack.
///
/// `RouteHint` identity-neutrality (ADR-008) is unaffected: the resolver
/// only reads `.value` for display; identity-bearing matching stays in
/// each tab's own `AppRouter.pushIfOnTop`.
struct RouteResolver: View {
  let route: Route
  @Environment(AppDependencies.self) private var dependencies

  var body: some View {
    switch route {
    case .scenarioDetail(let scenarioId, let initialName):
      ScenarioDetailView(scenarioId: scenarioId, initialName: initialName.value)
    case .editor(let editingId, let templateYAML):
      ScenarioEditorHost(
        repository: dependencies.scenarioRepository,
        editingId: editingId,
        templateYAML: templateYAML
      )
    case .simulation(let scenarioId, let initialName):
      SimulationView(scenarioId: scenarioId, initialName: initialName.value)
    case .results(let scenarioId):
      ResultsView(scope: .scenario(scenarioId))
    case .resultDetail(let simulationId):
      ResultDetailView(simulationId: simulationId)
    case .galleryScenarioDetail(let scenario):
      GalleryScenarioDetailView(scenario: scenario)
    }
  }
}

/// Host view that owns a ``ScenarioEditorViewModel`` via `@State`.
///
/// Needed so the ViewModel is retained across re-renders — creating it
/// inside a factory function would produce a fresh instance each time,
/// losing editor state. Moved here from `HomeView` alongside the resolver
/// (it is only used to build the `.editor` destination).
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
