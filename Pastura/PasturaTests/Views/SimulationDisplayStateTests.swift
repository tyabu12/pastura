import Testing

@testable import Pastura

/// Pure-logic coverage for
/// ``SimulationDisplayState/resolve(hasContent:isLoadingModel:isReloadingModel:isPlayingIntro:alreadyRunning:loadError:)``
/// — the derivation that drives `SimulationView`'s single persistent loading
/// scrim. View-testing.md rule 1: assert the derived state (locale-independent
/// enum), never rendered output. The spinner-continuity it enables is device-QA
/// (rule 4), out of scope here.
///
/// Precedence under test mirrors the pre-refactor body + overlay branch order:
/// content wins first — loadingModel > reloadingModel > running — then
/// alreadyRunning, then error, then the awaiting-scenario fallback. Exception:
/// `isPlayingIntro` suppresses `loadingModel` (the opening-card premise reveal
/// shows on a clean background while the model loads, #853), leaving
/// `reloadingModel` independent. The `alreadyRunning` / `error` arms are only
/// reachable while `viewModel == nil` in production (both set in
/// `SimulationView.task` before `loadAndRun`); the content-first case below
/// documents — not contradicts — that invariant. `hasContent` is the View's
/// `viewModel != nil && scenario != nil` gate.
@Suite(.timeLimit(.minutes(1)))
struct SimulationDisplayStateTests {
  private typealias State = SimulationDisplayState

  // MARK: - Content branch (hasContent == true)

  @Test func contentLoadingModelWinsWithinContent() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: true, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: false, loadError: nil) == .loadingModel)
  }

  @Test func contentReloadingModelWhenNotLoading() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: false, isReloadingModel: true,
        isPlayingIntro: false, alreadyRunning: false, loadError: nil) == .reloadingModel)
  }

  @Test func contentRunningWhenNeitherFlag() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: false, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: false, loadError: nil) == .running)
  }

  /// Both flags true: loadingModel wins (mirrors the old `if isLoadingModel
  /// else if isReloadingModel` overlay order).
  @Test func contentBothFlagsLoadingModelWins() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: true, isReloadingModel: true,
        isPlayingIntro: false, alreadyRunning: false, loadError: nil) == .loadingModel)
  }

  /// Content-first precedence: even with `alreadyRunning` / `loadError` set,
  /// a fully-built content surface resolves to a content state. In production
  /// this combination cannot occur (invariant: those flags imply no content);
  /// the case documents the ordering, it is not a bug.
  @Test func contentWinsOverAlreadyRunningAndError() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: false, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: true, loadError: "boom") == .running)
  }

  // MARK: - Intro suppression (isPlayingIntro == true, #853)

  /// While the opening-card premise is revealing, the model-load scrim is
  /// suppressed so the card types on a clean background — the load runs behind
  /// it. This is the whole point of the flag.
  @Test func introSuppressesLoadingModelScrim() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: true, isReloadingModel: false,
        isPlayingIntro: true, alreadyRunning: false, loadError: nil) == .running)
  }

  /// The suppression is scoped to `loadingModel` only. The mid-run GPU↔CPU
  /// `reloadingModel` scrim (ADR-003) stays independent — intro is a
  /// start-of-run beat and never overlaps a reload in practice, but the
  /// precedence encodes that rather than relying on timing.
  @Test func introDoesNotSuppressReloadingModelScrim() {
    #expect(
      State.resolve(
        hasContent: true, isLoadingModel: false, isReloadingModel: true,
        isPlayingIntro: true, alreadyRunning: false, loadError: nil) == .reloadingModel)
  }

  /// Intro playing without content is inert — the content gate is false, so the
  /// non-content fallback still wins (the flag is read as
  /// `viewModel?.isPlayingIntro ?? false`, only true once content exists).
  @Test func introWithoutContentFallsBackToAwaitingScenario() {
    #expect(
      State.resolve(
        hasContent: false, isLoadingModel: true, isReloadingModel: false,
        isPlayingIntro: true, alreadyRunning: false, loadError: nil) == .awaitingScenario)
  }

  // MARK: - Non-content branch (hasContent == false)

  @Test func awaitingScenarioWhenNothingSet() {
    #expect(
      State.resolve(
        hasContent: false, isLoadingModel: false, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: false, loadError: nil) == .awaitingScenario)
  }

  /// Without content, the model-loading flags are ignored — covers the
  /// non-atomic window where the view model is set a beat before the scenario
  /// (`startGuarded` then `scenario = parsed; viewModel = …`): the screen stays
  /// on the scenario-loading scrim, no flash.
  @Test func awaitingScenarioIgnoresLoadFlagsWithoutContent() {
    #expect(
      State.resolve(
        hasContent: false, isLoadingModel: true, isReloadingModel: true,
        isPlayingIntro: false, alreadyRunning: false, loadError: nil) == .awaitingScenario)
  }

  @Test func alreadyRunningWhenNoContent() {
    #expect(
      State.resolve(
        hasContent: false, isLoadingModel: false, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: true, loadError: nil) == .alreadyRunning)
  }

  @Test func errorWhenNoContentAndLoadError() {
    #expect(
      State.resolve(
        hasContent: false, isLoadingModel: false, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: false, loadError: "load failed")
        == .error("load failed"))
  }

  /// alreadyRunning takes precedence over error when both set (no content).
  @Test func alreadyRunningBeatsErrorWhenBothSet() {
    #expect(
      State.resolve(
        hasContent: false, isLoadingModel: false, isReloadingModel: false,
        isPlayingIntro: false, alreadyRunning: true, loadError: "load failed") == .alreadyRunning)
  }

  // MARK: - scrimLabel mapping

  @Test func scrimLabelMapping() {
    #expect(State.awaitingScenario.scrimLabel == .scenario)
    #expect(State.loadingModel.scrimLabel == .model)
    #expect(State.reloadingModel.scrimLabel == .reload)
    #expect(State.running.scrimLabel == nil)
    #expect(State.error("x").scrimLabel == nil)
    #expect(State.alreadyRunning.scrimLabel == nil)
  }
}
