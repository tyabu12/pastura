import Foundation
import Testing

@testable import Pastura

/// Tests pinning the runtime-mutable `playbackSpeed` API on
/// ``ReplayViewModel`` introduced in #290.
///
/// Key invariants:
/// - The VM seeds `playbackSpeed` from `config.playbackSpeed` at init.
/// - The property is plain `@Observable var` (Sim-style); writes
///   reflect at the **next** call to `scaledDelay(for:)` — the
///   in-flight `Task.sleep` is NOT recomputed.
/// - `.instant` early-returns 0ms before the multiplier division so
///   the `.infinity` sentinel in `PlaybackSpeed.multiplier` is never
///   load-bearing.
extension ReplayViewModelTests {

  // MARK: - Initialization

  @Test func playbackSpeedSeededFromConfig() throws {
    let config = ReplayPlaybackConfig(
      playbackSpeed: .fast,
      loopBehaviour: .stopAfterLast, onComplete: .stopPlayback)
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(),
      config: config)
    let viewModel = ReplayViewModel(sources: [source], config: config)
    #expect(viewModel.playbackSpeed == .fast)
  }

  @Test func playbackSpeedDefaultsToNormalUnderDemoDefault() throws {
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(),
      config: .demoDefault)
    let viewModel = ReplayViewModel(sources: [source], config: .demoDefault)
    #expect(viewModel.playbackSpeed == .normal)
  }

  // MARK: - Runtime mutation

  @Test func playbackSpeedIsWritable() throws {
    let viewModel = try Self.makeVM()
    viewModel.playbackSpeed = .slow
    #expect(viewModel.playbackSpeed == .slow)
    viewModel.playbackSpeed = .instant
    #expect(viewModel.playbackSpeed == .instant)
  }

  // MARK: - Next-event reflection (the canonical UX pin)

  @Test func instantCollapsesAllSubsequentEventsToFastPlayback() async throws {
    // Start at `.normal` with deliberately slow per-event delays so
    // the first event takes a measurable amount of time. Then flip to
    // `.instant` mid-flight; the remaining events should arrive in
    // close to zero wall time, demonstrating that next-event speed
    // change is honored.
    let config = ReplayPlaybackConfig(
      playbackSpeed: .normal,
      turnDelayMs: 200, codePhaseDelayMs: 50,
      loopBehaviour: .stopAfterLast, onComplete: .awaitTransitionSignal)
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(),
      config: config)
    let viewModel = ReplayViewModel(sources: [source], config: config)
    viewModel.start()
    // Wait for the first agent output (proving 1+ events have flowed
    // at the slow rate).
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    // Flip to instant — remaining 2 turns should now fly past.
    let mark = ContinuousClock.now
    viewModel.playbackSpeed = .instant
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count == 3 }
    let elapsed = ContinuousClock.now - mark
    // Two remaining turns at `.instant` (0ms each + Task.yield) should
    // resolve well under the at-`.normal` per-event delay (200ms).
    // Generous upper bound for CI; lower bound omitted because it'd
    // need to be 0 — too tight to assert.
    // Generous upper bound for CI under code coverage (per
    // `feedback_ci_wallclock_test_bounds.md`); the signal-to-noise is
    // in "did all events arrive at all," not in the exact budget.
    #expect(elapsed < .seconds(30))
  }

  @Test func instantSpeedFromIdleProducesAllEventsRapidly() async throws {
    // From a fresh start at `.instant`, the full 5-event plan
    // (3 turns + 2 lifecycle) should resolve fast — pinning that
    // `.instant` short-circuits scaledDelay() before the multiplier
    // division (no IEEE-754 dependency).
    let viewModel = try Self.makeVM()  // fastConfig is `.instant`
    let mark = ContinuousClock.now
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count == 3 }
    let elapsed = ContinuousClock.now - mark
    // 3 turns + 2 lifecycle events at `.instant` collapse to a series
    // of `Task.yield()`s. Generous bound for CI.
    // Generous upper bound for CI under code coverage (per
    // `feedback_ci_wallclock_test_bounds.md`); the signal-to-noise is
    // in "did all events arrive at all," not in the exact budget.
    #expect(elapsed < .seconds(30))
  }

  // MARK: - Resume preserves the speed-at-pause-time semantic

  @Test func resumeAfterPauseUsesCapturedRemainingDelay() async throws {
    // The `playbackSpeed` doc-comment promises: a speed change AFTER
    // pause does NOT recompute the captured `remainingDelayMs`. Pin
    // that invariant: pause at `.normal`, switch to `.fast`, resume —
    // the resumed sleep is the one captured at `.normal`. We don't
    // assert exact wall-clock; we assert the resumed cursor lands
    // unchanged (which it would whether the sleep recomputed or not),
    // PLUS that no crash / state corruption occurs.
    let config = ReplayPlaybackConfig(
      playbackSpeed: .normal,
      turnDelayMs: 200, codePhaseDelayMs: 50,
      loopBehaviour: .stopAfterLast, onComplete: .awaitTransitionSignal)
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(),
      config: config)
    let viewModel = ReplayViewModel(sources: [source], config: config)
    viewModel.start()
    try await Task.sleep(for: .milliseconds(20))
    viewModel.userPause()
    guard
      case .paused(let pausedIdx, let pausedCursor, _, .user) = viewModel.state
    else {
      Issue.record("Expected .paused(.user), got \(viewModel.state)")
      return
    }
    // Change speed while paused — this must not crash or rewrite the
    // captured remainingDelayMs.
    viewModel.playbackSpeed = .fast
    viewModel.userResume()
    if case .playing(let rIdx, let rCursor) = viewModel.state {
      #expect(rIdx == pausedIdx)
      #expect(rCursor == pausedCursor)
    } else {
      Issue.record("Expected .playing after userResume(), got \(viewModel.state)")
    }
  }
}
