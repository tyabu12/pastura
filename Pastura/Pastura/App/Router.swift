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

  /// Dual-mode (visual + YAML) scenario editor. Pass a scenario ID to
  /// edit, or nil for new. `templateYAML` pre-fills the editor from a
  /// preset (generates new ID). The YAML mode toolbar surfaces file
  /// picker + generation-prompt copy for the new-scenario flow.
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

  /// Past simulation results list — **Detail entry-point only** (e.g.
  /// tapping "Past Results" inside a ``ScenarioDetailView``). The resolver
  /// maps `scenarioId` to ``ResultsScope/scenario(_:)``, so this is
  /// per-variant: it surfaces simulations for *exactly* this scenario id
  /// even when a cross-language sibling exists with its own runs. This UX
  /// seam — a JA Detail's Past Results does NOT show EN sibling runs — is
  /// intentional, so a user reading a single-language scenario doesn't see
  /// semantically un-comparable sibling runs commingled.
  ///
  /// Cross-variant browsing is reserved for the History-tab root
  /// (``ResultsScope/aggregate``), which `RootTabView` mounts directly —
  /// it is **not** a `Route` push, so this case never carries an empty /
  /// aggregate id (ADR-010 D4 / #392, ADR-016 D4, #633).
  case results(scenarioId: String)

  /// Resume a previously-paused simulation run from the Home "interrupted run"
  /// card (ADR-016 P3, #667).
  ///
  /// Identity is the paused run's id (`simulationId`) — distinct from
  /// `.simulation`, whose identity is a `scenarioId`. `initialName` mirrors the
  /// other cases: a render-time hint (the run's scenario name) for the nav
  /// title from the first frame, identity-neutral via `RouteHint<String>`
  /// (ADR-008). `TabCoordinator.isSimulationOnTop` treats this case like
  /// `.simulation` — a resumed run is equally in-flight.
  case resumeSimulation(
    simulationId: String,
    initialName: RouteHint<String> = .init()
  )

  /// Detail view for a specific past simulation run.
  case resultDetail(simulationId: String)

  /// Detail view for a single gallery scenario, with Try / Update action.
  case galleryScenarioDetail(scenario: GalleryScenario)
}
