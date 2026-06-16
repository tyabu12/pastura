import Foundation

/// Selects which set of past simulation results ``ResultsView`` shows — the
/// type-checked replacement for the former empty-string `scenarioId`
/// sentinel (issue #633).
///
/// - ``aggregate``: the History-tab root. ``ResultsViewModel`` aggregates
///   simulations across language-variant siblings sharing a canonical
///   `ScenarioRecord.sourceId` (ADR-010 D4 / #392), and the view drops its
///   push back-chrome — it sits at the bottom of the tab's
///   `NavigationStack`, so there is nothing to pop to (ADR-016 D4).
/// - ``scenario(_:)``: a per-scenario detail push from a
///   ``ScenarioDetailView``. Per-variant only — a JA scenario does not
///   surface EN sibling runs; cross-variant browsing is reserved for the
///   aggregate root. Pushed via ``Route/results(scenarioId:)``.
///
/// The enum intentionally stops at the View boundary: the aggregate root is
/// mounted directly by `RootTabView`, never pushed through a `Route`, so
/// ``Route/results(scenarioId:)`` keeps a plain `scenarioId: String` (always
/// a real, non-empty id) rather than carrying a `.aggregate` case that could
/// never be generated.
enum ResultsScope {
  /// History-tab root — cross-variant aggregation of all past results.
  case aggregate
  /// Per-scenario detail push for exactly this scenario id.
  case scenario(String)

  /// `true` when the view is a pushed detail (``scenario(_:)``) and so needs
  /// the custom back-chrome; `false` for the ``aggregate`` tab root, which
  /// has no parent to pop to. Keys `PushBackChrome` in ``ResultsView``
  /// (issue #633, ADR-016 D4).
  var isPushedDetail: Bool {
    if case .scenario = self { return true }
    return false
  }
}
