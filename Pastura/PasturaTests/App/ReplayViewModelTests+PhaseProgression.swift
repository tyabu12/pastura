import Foundation
import Testing

@testable import Pastura

// Phase-progression + GameHeader-status tests for `ReplayViewModel`
// (PR 3 of #273 — header content unification). Sibling-file extension
// of `ReplayViewModelTests` per `.claude/rules/testing.md` — splitting
// to a fresh `@Suite` would race against the parent suite on shared
// state.
extension ReplayViewModelTests {

  // MARK: - Multi-phase fixture (for rotation re-derivation pinning)

  /// Two-phase scenario — speak_all then vote — required so the
  /// rotation test can verify `totalPhaseCount` actually re-derives
  /// against the new source (rather than holding stale value or
  /// zeroing).
  fileprivate static let twoPhaseScenarioYAML = """
    id: tp
    name: TwoPhase
    description: ''
    agents: 2
    rounds: 1
    context: ''
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
    phases:
      - type: speak_all
        prompt: say
        output:
          statement: string
      - type: vote
        prompt: vote
        output:
          target: string
    """

  /// Replay YAML covering both phases (one turn per phase).
  fileprivate static let twoPhaseReplayYAML = """
    schema_version: 1
    turns:
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hello' }
      - round: 1
        phase_index: 1
        phase_type: vote
        agent: Bob
        fields: { target: 'Alice' }
    """

  fileprivate static func makeTwoPhaseSource() throws -> YAMLReplaySource {
    let scenario = try ScenarioLoader().load(yaml: twoPhaseScenarioYAML)
    return try YAMLReplaySource(
      yaml: twoPhaseReplayYAML, scenario: scenario, config: fastConfig)
  }

  /// Hold-mode config for rotation tests — `.stopAfterLast` +
  /// `.awaitTransitionSignal` makes the VM hold at the last source's
  /// final cursor after rotating, so assertions don't race against
  /// premature teardown.
  fileprivate static let loopHoldConfig = ReplayPlaybackConfig(
    playbackSpeed: .normal,
    turnDelayMs: 150,
    codePhaseDelayMs: 50,
    loopBehaviour: .loop,
    onComplete: .awaitTransitionSignal)

  // MARK: - Polling helper

  /// Polls `condition` on the main actor until it returns true or the
  /// timeout elapses. Returns silently on either outcome (callers
  /// follow up with `#expect` against the observable state).
  ///
  /// Default timeout is 10s — well above the synchronous-ish state
  /// changes these tests poll on, but generous enough for CI's
  /// coverage-instrumented runs (memory: `feedback_ci_wallclock_test_bounds`
  /// recommends ≥30s for wall-clock waits; the loop costs nothing on
  /// green runs because it short-circuits the moment `condition()`
  /// returns true).
  static func waitForCondition(
    timeout: Duration = .seconds(10),
    _ condition: @MainActor () -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  // MARK: - Pre-start state

  @Test func preStartHasNilPhaseCountsAndDemoingStatus() throws {
    let viewModel = try Self.makeVM()
    #expect(viewModel.currentPhaseIndex == nil)
    #expect(viewModel.totalPhaseCount == nil)
    // `.idle` defaults to `.demoing` per the defensive fall-through;
    // the host view doesn't show the GameHeader pre-`start()` in
    // production but the public computed must be defined for all
    // states.
    #expect(viewModel.status == .demoing)
  }

  // MARK: - After start

  @Test func startPopulatesTotalPhaseCountForFirstSource() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    // `start()` synchronously enters `.playing` and pre-computes
    // `cachedTotalPhaseCount` against `sources[0]`. The threeTurn
    // scenario has 1 phase (`speak_all`), so total = 1.
    #expect(viewModel.totalPhaseCount == 1)
    #expect(viewModel.status == .demoing)
    // currentPhaseIndex stays nil until the first `.phaseStarted`
    // event is consumed by the playback task — that happens
    // asynchronously after `start()` returns.
  }

  // MARK: - Phase consumption

  @Test func consumingPhaseStartedIncrementsCurrentIndex() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    #expect(viewModel.currentPhaseIndex == 1)
    // For the single-phase threeTurn fixture, the index never goes
    // above 1; subsequent `.agentOutput` / `.scoreUpdate` events
    // don't increment.
    #expect(viewModel.totalPhaseCount == 1)
  }

  // MARK: - Pause keeps ROUND fragment visible (#355 follow-up)

  @Test func userPauseKeepsPhaseCountsAndFlipsStatusToPaused() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    viewModel.userPause()
    // ROUND fragment stays put so the user retains the position
    // context while paused. Status pill flips to `.paused` to make
    // the pause-vs-play distinction obvious without dropping ROUND
    // visibility. Original #297 PR3 spec collapsed both fragments;
    // re-evaluated in #355 follow-up — the collapse was conflating
    // playback state with identity state (cf. #355 avatar-color
    // and scenarioName regressions, same root cause).
    #expect(viewModel.currentPhaseIndex == 1)
    #expect(viewModel.totalPhaseCount == 1)
    #expect(viewModel.status == .paused)
  }

  @Test func scenePhasePauseAlsoKeepsPhaseCounts() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    viewModel.onBackground()
    // Same rule applies on the scene-phase auto-pause path — the
    // UI is normally hidden during BG anyway, but the boundary is
    // meaningful for the transient FG-redraw frame.
    #expect(viewModel.currentPhaseIndex == 1)
    #expect(viewModel.totalPhaseCount == 1)
    #expect(viewModel.status == .paused)
  }

  // MARK: - Resume flips status without changing ROUND values

  @Test func userResumeKeepsPhaseCountsAndFlipsStatusBackToDemoing() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    viewModel.userPause()
    viewModel.userResume()
    // Underlying counter is unchanged across the pause / resume
    // round-trip; the visible difference is only the status pill.
    #expect(viewModel.currentPhaseIndex == 1)
    #expect(viewModel.totalPhaseCount == 1)
    #expect(viewModel.status == .demoing)
  }

  // MARK: - Transitioning hides ROUND but keeps status .demoing

  @Test func downloadCompleteHidesPhaseCountsButKeepsStatusDemoing() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
    #expect(viewModel.currentPhaseIndex == nil)
    #expect(viewModel.totalPhaseCount == nil)
    // Status stays `.demoing` during the brief fade — header co-fades
    // with the demo body, so flipping the pill mid-fade would draw
    // attention to a chrome change at exactly the wrong moment.
    #expect(viewModel.status == .demoing)
  }

  // MARK: - Loop rotation re-derives totalPhaseCount

  @Test func loopRotationReDerivesTotalPhaseCountAgainstNewSource() async throws {
    // Source 0: threeTurn scenario, 1 phase (speak_all).
    // Source 1: twoPhase scenario, 2 phases (speak_all + vote).
    // After rotation source 0 → source 1, totalPhaseCount must
    // re-derive to 2 — proves the cache is bound to the current
    // source, not pinned to source 0.
    let source0 = try Self.makeSource()  // 1 phase
    let source1 = try Self.makeTwoPhaseSource()  // 2 phases
    let viewModel = ReplayViewModel(
      sources: [source0, source1], config: Self.loopHoldConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Initial totalPhaseCount = 1 (source 0).
    #expect(viewModel.totalPhaseCount == 1)
    // Wait for rotation to source 1. Generous wall-clock bound for
    // CI's coverage-instrumented runs (per
    // `feedback_ci_wallclock_test_bounds` memory).
    await Self.waitForCondition(timeout: .seconds(30)) {
      if case .playing(let idx, _) = viewModel.state { return idx >= 1 }
      return false
    }
    // After rotation, totalPhaseCount = 2 (source 1's phase count) —
    // and currentPhaseIndex resets to nil until source 1's first
    // `.phaseStarted` is consumed.
    #expect(viewModel.totalPhaseCount == 2)
    // `currentPhaseIndex` may be nil (just rotated) or 1 (already
    // consumed source 1's first phaseStarted) depending on timing —
    // both are valid post-rotation states. The load-bearing assertion
    // is that it did NOT stay at 1 from source 0 with stale total.
    #expect(viewModel.currentPhaseIndex == nil || viewModel.currentPhaseIndex == 1)
    #expect(viewModel.status == .demoing)
  }

  // MARK: - headerRound (GameHeader pair wrapper, #313)

  @Test func headerRoundIsNilPreStart() throws {
    let viewModel = try Self.makeVM()
    #expect(viewModel.headerRound == nil)
  }

  @Test func headerRoundIsNilBetweenStartAndFirstPhaseStarted() async throws {
    // `start()` sets `cachedTotalPhaseCount` synchronously but
    // `phaseProgress` stays at `0` until the playback task consumes
    // the first `.phaseStarted`. The wrapper must collapse to nil in
    // that intermediate window — proving it doesn't leak a partial
    // pair (`current: nil, total: 1`) to the GameHeader.
    let viewModel = try Self.makeVM()
    viewModel.start()
    // totalPhaseCount is non-nil immediately, but currentPhaseIndex
    // is still nil → headerRound must be nil.
    #expect(viewModel.totalPhaseCount == 1)
    #expect(viewModel.currentPhaseIndex == nil)
    #expect(viewModel.headerRound == nil)
  }

  @Test func headerRoundReflectsPhaseConsumption() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    #expect(viewModel.headerRound == GameHeaderRound(current: 1, total: 1))
  }

  @Test func headerRoundStaysAvailableDuringPause() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    viewModel.userPause()
    // Mirrors `userPauseKeepsPhaseCountsAndFlipsStatusToPaused` —
    // headerRound is the GameHeader-facing pair wrapper and inherits
    // the new `.playing` + `.paused` policy automatically.
    #expect(viewModel.headerRound == GameHeaderRound(current: 1, total: 1))
  }

  @Test func headerRoundStaysAvailableDuringScenePhasePause() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForCondition { viewModel.currentPhaseIndex != nil }
    viewModel.onBackground()
    #expect(viewModel.headerRound == GameHeaderRound(current: 1, total: 1))
  }
}
