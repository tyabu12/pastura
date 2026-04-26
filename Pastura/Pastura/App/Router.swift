import Foundation

/// Navigation destinations for the app's `NavigationStack`.
///
/// Each case carries the minimum data needed to construct the destination view.
/// Used with `NavigationStack(path:)` for programmatic navigation.
enum Route: Hashable {
  /// Scenario detail screen.
  ///
  /// `initialName` is a render-time hint used to display the scenario
  /// name in the navigation title from the first frame of the push,
  /// before `ScenarioDetailViewModel.load(...)` completes its DB +
  /// YAML parse. Wrapped in `RouteHint<String>` so the value does
  /// **not** participate in `Route` Hashable identity — `pushIfOnTop`
  /// guards comparing two `.scenarioDetail` values match on
  /// `scenarioId` regardless of whether the hint differs.
  /// See `docs/decisions/ADR-008.md` for the full rationale.
  case scenarioDetail(
    scenarioId: String,
    initialName: RouteHint<String> = .init()
  )

  /// YAML import screen. Pass an existing scenario ID to edit.
  case importScenario(editingId: String? = nil)

  /// Visual scenario editor. Pass a scenario ID to edit, or nil for new.
  /// `templateYAML` pre-fills the editor from a preset (generates new ID).
  case editor(editingId: String? = nil, templateYAML: String? = nil)

  /// Live simulation execution screen.
  ///
  /// `initialName` mirrors `.scenarioDetail` — render-time hint for
  /// the navigation title so the bar shows the scenario name from the
  /// first frame of the push, before `loadAndRun()` completes.
  /// Identity-neutral via `RouteHint<String>` (ADR-008).
  case simulation(
    scenarioId: String,
    initialName: RouteHint<String> = .init()
  )

  /// Past simulation results list for a scenario.
  case results(scenarioId: String)

  /// Detail view for a specific past simulation run.
  case resultDetail(simulationId: String)

  /// Share Board — browse a curated gallery of scenarios.
  case shareBoard

  /// Detail view for a single gallery scenario, with Try / Update action.
  case galleryScenarioDetail(scenario: GalleryScenario)

  /// Settings screen — content-reporting disclosure and future
  /// configuration surfaces.
  case settings
}
