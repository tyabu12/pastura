import Foundation
import Testing

@testable import Pastura

// Source-rotation + loop-behaviour tests for `ReplayViewModel`.
// Sibling-file extension per `.claude/rules/testing.md`.
extension ReplayViewModelTests {

  // MARK: - Fixtures

  fileprivate static func makeTwoSources() throws -> [YAMLReplaySource] {
    let yaml1 = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'demo 1 alice' }
      """
    let yaml2 = """
      schema_version: 1
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'demo 2 bob' }
      """
    let scenario = try makeScenario()
    return [
      try YAMLReplaySource(yaml: yaml1, scenario: scenario, config: fastConfig),
      try YAMLReplaySource(yaml: yaml2, scenario: scenario, config: fastConfig)
    ]
  }

  /// Rotation-observable pacing: 150 ms per turn event at 1× speed.
  /// Each source plays in ~150 ms, so between-source observation
  /// windows are comfortably larger than the test poll interval
  /// (5 ms). Faster configs (see `fastConfig` in the main suite file)
  /// collapse delays to 0 ms + `Task.yield()` which makes rotation
  /// cycle sub-ms — rotation assertions race against the poll loop.
  fileprivate static let stopConfig = ReplayPlaybackConfig(
    speedMultiplier: 1.0,
    turnDelayMs: 150,
    codePhaseDelayMs: 50,
    loopBehaviour: .stopAfterLast,
    onComplete: .stopPlayback)

  fileprivate static let holdConfig = ReplayPlaybackConfig(
    speedMultiplier: 1.0,
    turnDelayMs: 150,
    codePhaseDelayMs: 50,
    loopBehaviour: .stopAfterLast,
    onComplete: .awaitTransitionSignal)

  fileprivate static let loopConfig = ReplayPlaybackConfig(
    speedMultiplier: 1.0,
    turnDelayMs: 150,
    codePhaseDelayMs: 50,
    loopBehaviour: .loop,
    onComplete: .awaitTransitionSignal)

  // MARK: - Source rotation

  @Test func rotatesToNextSourceOnStreamEndWithLoop() async throws {
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.loopConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Wait until the VM has rotated from source 0 to source 1.
    await Self.waitForState(viewModel) { state in
      if case .playing(let idx, _) = state { return idx >= 1 }
      return false
    }
    if case .playing(let idx, _) = viewModel.state {
      #expect(idx == 1)
    } else {
      Issue.record("Expected .playing on source 1 after rotation, got \(viewModel.state)")
    }
  }

  @Test func rotationClearsPerDemoObservableState() async throws {
    // Uses `holdConfig` (stopAfterLast + awaitTransitionSignal) rather
    // than `loopConfig`, so the test observes a deterministic
    // source-0 → source-1 transition without racing against loop
    // wraparound. After rotation completes the VM holds at
    // `.playing(1, 3)` — agentOutputs is source 1's only.
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.holdConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Wait until the VM has hit source 1's final cursor (3 events =
    // 2 lifecycle + 1 turn). At that point rotation has happened and
    // source 1's turn has published.
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 3 {
        return true
      }
      return false
    }
    // agentOutputs must be source 1's only — rotation's
    // `resetPerDemoState()` cleared source 0's entry.
    #expect(viewModel.agentOutputs.count == 1)
    #expect(viewModel.agentOutputs[0].output.statement == "demo 2 bob")
  }

  @Test func loopWrapsAroundAfterLastSource() async throws {
    // Two sources, .loop config. The VM should visit idx 0 → 1 → 0
    // (wrap-around) within the wall-clock budget. We track the
    // source-index progression to distinguish the initial play of
    // source 0 from the wrap-around play of source 0.
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.loopConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Step 1: wait for the VM to reach source 1 (end of first cycle
    // through source 0).
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, _) = state { return idx >= 1 }
      return false
    }
    // Step 2: wait for wrap-around — the VM must leave source 1 and
    // return to source 0. Watch for the transition itself (idx goes
    // from 1 back to 0) rather than a content match, which can race
    // against the loop cycle.
    var sawSource1 = false
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      guard case .playing(let idx, _) = state else { return false }
      if idx == 1 { sawSource1 = true }
      return sawSource1 && idx == 0
    }
    if case .playing(let idx, _) = viewModel.state {
      #expect(idx == 0, "wrap-around to source 0 expected, got idx=\(idx)")
    } else {
      Issue.record("Expected wrap-around to source 0, got \(viewModel.state)")
    }
  }

  // MARK: - stopAfterLast terminal states

  @Test func stopAfterLastWithStopPlaybackReturnsToIdle() async throws {
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.stopConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Wait for terminal .idle state.
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      state == .idle
    }
    #expect(viewModel.state == .idle)
  }

  @Test func stopAfterLastWithAwaitTransitionHoldsUntilDownloadComplete() async throws {
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.holdConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Wait for the VM to reach the last source's plan-end state.
    // With 2 sources × 1 turn + 2 lifecycle = 3 events per source,
    // the final resting cursor on the last source is 3.
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 3 {
        return true
      }
      return false
    }
    if case .playing(let idx, _) = viewModel.state {
      #expect(idx == 1)
    } else {
      Issue.record("Expected .playing held on last source, got \(viewModel.state)")
    }
    // Now the transition signal arrives — VM moves to .transitioning.
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
  }

  // MARK: - Infinite loop guarded by downloadComplete

  @Test func loopConfigDoesNotTerminateWithoutDownloadComplete() async throws {
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.loopConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Give the loop time to rotate a few times.
    try await Task.sleep(for: .milliseconds(300))
    // Must still be playing — loop config does not surface a
    // terminal state without an external signal.
    switch viewModel.state {
    case .playing:
      break  // expected
    default:
      Issue.record(
        "Loop config must not terminate without downloadComplete, got \(viewModel.state)")
    }
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
  }
}
