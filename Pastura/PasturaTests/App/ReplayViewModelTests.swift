import Foundation
import Testing

@testable import Pastura

/// Swift Testing suite for ``ReplayViewModel``.
///
/// `.serialized` per `.claude/rules/testing.md` — the VM spawns a
/// `Task` + consumes `AsyncStream`-style async work, so parallel
/// execution with other VM-spawning tests would risk cleanup races on
/// the shared test process.
@Suite("ReplayViewModel", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ReplayViewModelTests {

  // MARK: - Fixtures

  static let scenarioYAML = """
    id: ts
    name: Test
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
    """

  /// Three-turn demo: Alice speaks, Bob speaks, Alice speaks again.
  /// Plus lifecycle synthesis → 5 total PacedEvents (roundStarted,
  /// phaseStarted, 3 turns).
  static let threeTurnYAML = """
    schema_version: 1
    turns:
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hello' }
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Bob
        fields: { statement: 'hi there' }
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'nice to meet you' }
    """

  static func makeScenario() throws -> Scenario {
    try ScenarioLoader().load(yaml: scenarioYAML)
  }

  /// Fast pacing: `.instant` collapses every per-event sleep to 0 —
  /// tests still observe the state machine transitions without paying
  /// human-scale wait times. (Pre-#290 used `speedMultiplier: 100.0`
  /// for ~12 ms turns; the new shape is strictly faster but no test
  /// here pins on the residual delay.)
  ///
  /// Uses `.stopAfterLast + .awaitTransitionSignal` so the VM HOLDS at
  /// `.playing(lastIndex, plan.count)` after the single source's plan
  /// is exhausted — otherwise most tests below would race against
  /// premature termination. Rotation-specific tests override with
  /// their own config (see `ReplayViewModelTests+Rotation.swift`).
  static let fastConfig = ReplayPlaybackConfig(
    playbackSpeed: .instant,
    turnDelayMs: 20,
    codePhaseDelayMs: 5,
    loopBehaviour: .stopAfterLast,
    onComplete: .awaitTransitionSignal)

  static func makeSource(yaml: String = threeTurnYAML) throws -> YAMLReplaySource {
    try YAMLReplaySource(yaml: yaml, scenario: makeScenario(), config: fastConfig)
  }

  static func makeVM(yaml: String = threeTurnYAML) throws -> ReplayViewModel {
    let source = try makeSource(yaml: yaml)
    return ReplayViewModel(
      sources: [source], config: fastConfig, contentFilter: ContentFilter())
  }

  /// Polls `state` on the main actor until `predicate` is true or the
  /// timeout elapses. Returns when the predicate matches.
  static func waitForState(
    _ viewModel: ReplayViewModel, timeout: Duration = .seconds(2),
    predicate: @MainActor (ReplayViewModel.State) -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if predicate(viewModel.state) { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  // MARK: - Initial state

  @Test func initialStateIsIdle() throws {
    let viewModel = try Self.makeVM()
    #expect(viewModel.state == .idle)
    #expect(viewModel.currentPhase == nil)
    #expect(viewModel.currentRound == nil)
    #expect(viewModel.currentTotalRounds == nil)
    #expect(viewModel.agentOutputs.isEmpty)
  }

  // MARK: - start() and basic playback

  @Test func startTransitionsFromIdleToPlaying() throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    // The state machine moves synchronously to `.playing(0, 0)` before
    // the first sleep; subsequent `playing(..., N)` steps happen as
    // the playback task runs.
    if case .playing(let idx, _) = viewModel.state {
      #expect(idx == 0)
    } else {
      Issue.record("Expected .playing immediately after start(), got \(viewModel.state)")
    }
  }

  @Test func startIsNoOpWhenAlreadyPlaying() throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    let firstState = viewModel.state
    viewModel.start()
    #expect(viewModel.state == firstState)
  }

  @Test func playbackEventuallyReachesPlanEnd() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    // 3 turns + 2 lifecycle = 5 events in the plan.
    await Self.waitForState(viewModel) { state in
      if case .playing(_, let cursor) = state { return cursor >= 5 }
      return false
    }
    if case .playing(_, let cursor) = viewModel.state {
      #expect(cursor == 5)
    } else {
      Issue.record("Expected .playing at plan end, got \(viewModel.state)")
    }
  }

  @Test func agentOutputsAccumulateInPublishOrder() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count == 3 }
    #expect(viewModel.agentOutputs.count == 3)
    #expect(viewModel.agentOutputs[0].agent == "Alice")
    #expect(viewModel.agentOutputs[1].agent == "Bob")
    #expect(viewModel.agentOutputs[2].agent == "Alice")
    #expect(viewModel.agentOutputs[0].output.statement == "hello")
  }

  @Test func lifecycleEventsUpdateObservableState() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.currentPhase != nil }
    #expect(viewModel.currentPhase == .speakAll)
    #expect(viewModel.currentRound == 1)
    // Scenario yaml declares `rounds: 1`.
    #expect(viewModel.currentTotalRounds == 1)
  }

  // MARK: - onBackground / onForeground

  @Test func onBackgroundTransitionsPlayingToPaused() async throws {
    // Slow pacing (`.normal` = 1×) so we can catch the VM mid-sleep.
    // turnDelayMs=200ms × 1.0 = 200ms per event; calling onBackground
    // ~20ms after start catches the first sleep in progress.
    let slowConfig = ReplayPlaybackConfig(
      playbackSpeed: .normal,
      turnDelayMs: 200, codePhaseDelayMs: 50,
      loopBehaviour: .stopAfterLast, onComplete: .stopPlayback)
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(),
      config: slowConfig)
    let viewModel = ReplayViewModel(sources: [source], config: slowConfig)
    viewModel.start()
    // Sleep briefly so the playback task begins its first sleep.
    try await Task.sleep(for: .milliseconds(20))
    viewModel.onBackground()
    if case .paused(let idx, let cursor, let remaining, let reason) =
      viewModel.state {
      #expect(idx == 0)
      // Cursor is 0 (we haven't published the first roundStarted yet
      // because lifecycle delay is 0 — actually 0-delay "sleeps"
      // complete immediately, so cursor may have advanced past the 2
      // lifecycle events by the time we grab state). Just assert the
      // state shape.
      #expect(cursor >= 0)
      #expect(remaining >= 0)
      // onBackground() always tags pauses as `.scenePhase`; assertion
      // strengthening per critic Axis 2 (PR 1b).
      #expect(reason == .scenePhase)
    } else {
      Issue.record("Expected .paused, got \(viewModel.state)")
    }
  }

  @Test func onBackgroundFromIdleIsNoOp() throws {
    let viewModel = try Self.makeVM()
    viewModel.onBackground()
    #expect(viewModel.state == .idle)
  }

  @Test func onForegroundResumesFromPausedPosition() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    // Wait for some progress.
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.onBackground()
    guard case .paused(let idx, let cursor, _, .scenePhase) = viewModel.state
    else {
      Issue.record("Expected .paused(.scenePhase) after onBackground, got \(viewModel.state)")
      return
    }
    viewModel.onForeground()
    // Resume moves back to .playing at the same (sourceIndex, cursor).
    if case .playing(let rIdx, let rCursor) = viewModel.state {
      #expect(rIdx == idx)
      #expect(rCursor == cursor)
    } else {
      Issue.record("Expected .playing after onForeground, got \(viewModel.state)")
    }
    // Playback eventually reaches the plan end.
    await Self.waitForState(viewModel) { state in
      if case .playing(_, let cursor) = state { return cursor >= 5 }
      return false
    }
    #expect(viewModel.agentOutputs.count == 3)
  }

  @Test func onForegroundFromIdleIsNoOp() throws {
    let viewModel = try Self.makeVM()
    viewModel.onForeground()
    #expect(viewModel.state == .idle)
  }

  // MARK: - downloadComplete()

  @Test func downloadCompleteFromPlayingTransitions() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
  }

  @Test func downloadCompleteFromPausedTransitions() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.onBackground()
    #expect({ if case .paused = viewModel.state { return true } else { return false } }())
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
  }

  @Test func downloadCompleteFromIdleIsNoOp() throws {
    let viewModel = try Self.makeVM()
    viewModel.downloadComplete()
    #expect(viewModel.state == .idle)
  }
}
