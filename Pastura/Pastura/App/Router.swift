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

  /// Past simulation results list.
  ///
  /// Two semantics based on `scenarioId`:
  ///
  /// - **Empty (`""`)** — Home entry-point. ``ResultsViewModel``
  ///   aggregates simulations across language-variant siblings
  ///   sharing a canonical `ScenarioRecord.sourceId` (ADR-010 D4 /
  ///   #392). Each section's header uses the device-locale variant's
  ///   `name`; rows preserve the simulation-time variant's own name.
  /// - **Non-empty** — Detail entry-point (e.g. tapping "Past
  ///   Results" inside a ``ScenarioDetailView``). Per-variant only:
  ///   surfaces simulations for *exactly* this scenario id even when
  ///   a cross-language sibling exists with its own runs. This UX
  ///   seam — a JA Detail's Past Results does NOT show EN sibling
  ///   runs — is intentional, so a user reading a single-language
  ///   scenario doesn't see semantically un-comparable sibling runs
  ///   commingled. Cross-variant browsing is reserved for Home.
  case results(scenarioId: String)

  /// Detail view for a specific past simulation run.
  case resultDetail(simulationId: String)

  /// Detail view for a single gallery scenario, with Try / Update action.
  case galleryScenarioDetail(scenario: GalleryScenario)
}
