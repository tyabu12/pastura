/// View-presentation state for ``SimulationView``, derived purely from the
/// view's input flags so the *derivation* is unit-testable without rendering
/// the View (ADR-009 / `.claude/rules/view-testing.md` rule 1). The animation
/// continuity it enables is verified by device QA (rule 4), not here.
///
/// `nonisolated` (rather than the `@MainActor`-test default in
/// `.claude/rules/swift-isolation.md` Pattern 5) is intentional: this is pure
/// presentation data with no MainActor reason, so marking the type
/// `nonisolated` releases its auto-synthesized `Equatable` conformance for use
/// from the nonisolated test suite (Pattern 5, fix option 2). Do not add a
/// MainActor-only member.
nonisolated enum SimulationDisplayState: Equatable {
  /// Scenario YAML still loading; the view model / content does not exist yet.
  /// Scrim shows "Loading scenario...".
  case awaitingScenario
  /// Content built; the LLM model is loading at run / resume start (before the
  /// first event). Scrim shows "Loading model...".
  case loadingModel
  /// Content built and running; the model is being reloaded for a background
  /// GPU↔CPU switch. Scrim shows "Reloading model...".
  case reloadingModel
  /// Content built; simulation running normally. No scrim.
  case running
  /// Scenario / record load failed before the view model existed.
  case error(String)
  /// A different run already owns the session; show the return-to-run prompt.
  case alreadyRunning

  /// Which loading message the single persistent scrim should show, or `nil`
  /// when no scrim is shown. Returned as a case (not a localized `String`) so
  /// the derivation tests stay locale-independent — ``SimulationView`` maps
  /// each case to its `String(localized:)` literal.
  enum ScrimLabel: Equatable {
    case scenario
    case model
    case reload
  }

  /// The scrim label for this state, or `nil` when no scrim should show. The
  /// scrim stays mounted (same view identity) as long as this is non-`nil`,
  /// which is what keeps the spinner continuous across
  /// ``awaitingScenario`` → ``loadingModel``.
  var scrimLabel: ScrimLabel? {
    switch self {
    case .awaitingScenario: .scenario
    case .loadingModel: .model
    case .reloadingModel: .reload
    case .running, .error, .alreadyRunning: nil
    }
  }

  /// Derives the display state from ``SimulationView``'s inputs, preserving the
  /// pre-existing body + overlay branch precedence exactly: content wins first
  /// — within it `loadingModel` > `reloadingModel` > `running` — then
  /// `alreadyRunning`, then `error`, then the scenario-loading fallback.
  ///
  /// `hasContent` is the View's `viewModel != nil && scenario != nil` gate
  /// collapsed to a single flag (they are only ever used together). Until both
  /// land — including the non-atomic window where the view model is set a beat
  /// before the scenario — `hasContent` is `false` and the scenario-loading
  /// scrim shows; the `isLoadingModel` / `isReloadingModel` flags are ignored
  /// without content.
  ///
  /// Invariant: `alreadyRunning` / `loadError` are only ever set while
  /// `viewModel == nil` (both are assigned in `SimulationView.task` before
  /// `loadAndRun`), so the content-first ordering never masks them in practice.
  /// Do not "fix" the content-first precedence as if it could shadow those.
  static func resolve(
    hasContent: Bool,
    isLoadingModel: Bool,
    isReloadingModel: Bool,
    alreadyRunning: Bool,
    loadError: String?
  ) -> SimulationDisplayState {
    if hasContent {
      if isLoadingModel { return .loadingModel }
      if isReloadingModel { return .reloadingModel }
      return .running
    }
    if alreadyRunning { return .alreadyRunning }
    if let loadError { return .error(loadError) }
    return .awaitingScenario
  }
}
