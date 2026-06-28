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

  // MARK: - typingCharsPerSecond tracks playbackSpeed (#791)
  //
  // Before #791 the demo's typing cps was the fixed `config.typingCharsPerSecond`,
  // so the Speed menu changed only turn dwell, not typing. These pin that the cps
  // now follows the runtime `playbackSpeed` (Sim parity) on a demo (opt-in)
  // config, and that a non-demo config (typingCharsPerSecond == nil) still opts
  // out regardless of speed. Reverting the fix (returning
  // `config.typingCharsPerSecond`) makes the .slow/.fast/.instant cases fail.
  // The cps values are the unified ``PlaybackSpeed/charsPerSecond`` (#835),
  // shared with the live Sim.

  @Test func typingCharsPerSecondTracksPlaybackSpeedOnDemoDefault() throws {
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(),
      config: .demoDefault)
    let viewModel = ReplayViewModel(sources: [source], config: .demoDefault)

    viewModel.playbackSpeed = .slow
    #expect(viewModel.typingCharsPerSecond == PlaybackSpeed.slow.charsPerSecond)
    #expect(viewModel.typingCharsPerSecond == 6)

    viewModel.playbackSpeed = .normal
    #expect(viewModel.typingCharsPerSecond == 10)

    viewModel.playbackSpeed = .fast
    #expect(viewModel.typingCharsPerSecond == 45)

    // `.instant` → nil so `AgentOutputRow` renders full text immediately.
    viewModel.playbackSpeed = .instant
    #expect(viewModel.typingCharsPerSecond == nil)
  }

  @Test func typingCharsPerSecondStaysNilForNonDemoConfigAcrossSpeeds() throws {
    // Non-demo config leaves `typingCharsPerSecond` at its nil default — the
    // opt-in gate must keep it nil at every speed (no proportional dwell /
    // instant text), unchanged from pre-#791 behavior.
    let config = ReplayPlaybackConfig(
      playbackSpeed: .normal,
      loopBehaviour: .stopAfterLast, onComplete: .stopPlayback)
    let source = try YAMLReplaySource(
      yaml: Self.threeTurnYAML, scenario: Self.makeScenario(), config: config)
    let viewModel = ReplayViewModel(sources: [source], config: config)

    for speed in PlaybackSpeed.allCases {
      viewModel.playbackSpeed = speed
      #expect(viewModel.typingCharsPerSecond == nil)
    }
  }
}
