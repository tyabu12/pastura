import Foundation
import Testing

@testable import Pastura

// chatItems-accumulation regression tests for `ReplayViewModel` (#208).
// Sibling-file extension per `.claude/rules/testing.md`. Split out from
// `ReplayViewModelTests+Rotation.swift` to keep both files under
// SwiftLint's `file_length` ceiling.
//
// File-scope helpers carry the YAML fixtures so the per-test bodies and
// the `makeTwoSourcesWithDistinctScenarios()` factory stay under the
// `function_body_length` cap (#208 plan-time miss surfaced this — see
// memory entry "wc -l before planning Swift edits").

private let firstScenarioYAML = """
  id: first
  language: ja
  name: First Scenario
  description: ''
  agents: 1
  rounds: 1
  context: ''
  personas:
    - name: Alice
      description: ''
  phases:
    - type: speak_all
      prompt: say
      output:
        statement: string
  """

private let secondScenarioYAML = """
  id: second
  language: ja
  name: Second Scenario
  description: ''
  agents: 1
  rounds: 1
  context: ''
  personas:
    - name: Bob
      description: ''
  phases:
    - type: speak_all
      prompt: say
      output:
        statement: string
  """

private let firstSourceTurnsYAML = """
  schema_version: 1
  turns:
    - round: 1
      phase_index: 0
      phase_type: speak_all
      agent: Alice
      fields: { statement: 'first' }
  """

private let secondSourceTurnsYAML = """
  schema_version: 1
  turns:
    - round: 1
      phase_index: 0
      phase_type: speak_all
      agent: Bob
      fields: { statement: 'second' }
  """

extension ReplayViewModelTests {

  /// Two sources backed by DISTINCT scenarios (different `name`
  /// fields). Disambiguates `sources[nextIndex].scenario.name` from
  /// `sources[currentIndex].scenario.name`: the wrong-direction
  /// implementation would silently pass against fixtures that share
  /// names (e.g. `makeTwoSources()`'s "Test"/"Test").
  fileprivate static func makeTwoSourcesWithDistinctScenarios() throws
    -> [YAMLReplaySource] {
    let firstScenario = try ScenarioLoader().load(yaml: firstScenarioYAML)
    let secondScenario = try ScenarioLoader().load(yaml: secondScenarioYAML)
    return [
      try YAMLReplaySource(
        yaml: firstSourceTurnsYAML, scenario: firstScenario, config: fastConfig),
      try YAMLReplaySource(
        yaml: secondSourceTurnsYAML, scenario: secondScenario, config: fastConfig)
    ]
  }

  // MARK: - Tests

  @Test func boundaryMarkerCarriesNextSourceScenarioName() async throws {
    let sources = try Self.makeTwoSourcesWithDistinctScenarios()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.holdConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 3 {
        return true
      }
      return false
    }
    let boundaryNames = viewModel.chatItems.compactMap { item -> String? in
      if case .demoBoundary(_, let name) = item { return name }
      return nil
    }
    #expect(boundaryNames.count == 1)
    #expect(
      boundaryNames.first == "Second Scenario",
      "Boundary must carry sources[nextIndex].scenario.name (the demo about to start), not the just-finished one"
    )
  }

  @Test func loopWrapClearsChatItemsWithoutBoundaryMarker() async throws {
    // 2 sources × `.loop` config. After source 1 plays the wrap branch
    // wipes `chatItems` and does NOT insert a boundary marker — the
    // visual reset itself signals the new cycle.
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.loopConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Step 1: wait for source 1 to fully play through. At this moment
    // chatItems = [Alice, boundary, Bob].
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 3 {
        return true
      }
      return false
    }
    // Step 2: wait for the wrap-around — source 1 → source 0.
    var sawSource1 = false
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      guard case .playing(let idx, _) = state else { return false }
      if idx == 1 { sawSource1 = true }
      return sawSource1 && idx == 0
    }
    // After wrap: no boundary markers (the wipe + no-marker policy),
    // and the accumulator is bounded by source 0's content alone — at
    // most 1 agent output if Alice already re-published.
    let boundaryCount = viewModel.chatItems.reduce(0) { acc, item in
      if case .demoBoundary = item { return acc + 1 }
      return acc
    }
    #expect(
      boundaryCount == 0,
      "Loop wrap must wipe boundaries, got \(viewModel.chatItems)")
    #expect(
      viewModel.chatItems.count <= 1,
      "Loop wrap must wipe accumulator, got count=\(viewModel.chatItems.count)")
  }

  @Test func chatItemsSurvivesBackgroundForegroundRoundTrip() async throws {
    // Pause/resume should not touch the accumulator. Capture chatItems
    // post-rotation, BG → FG, then verify it is byte-identical.
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.holdConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 3 {
        return true
      }
      return false
    }
    let preBackgroundCount = viewModel.chatItems.count
    let preBackgroundIds = viewModel.chatItems.map(\.id)
    #expect(preBackgroundCount == 3)

    viewModel.onBackground()
    if case .paused(_, _, _, .scenePhase) = viewModel.state {
      // expected
    } else {
      Issue.record(
        "Expected .paused(.scenePhase) after onBackground, got \(viewModel.state)")
    }
    viewModel.onForeground()

    #expect(viewModel.chatItems.count == preBackgroundCount)
    #expect(viewModel.chatItems.map(\.id) == preBackgroundIds)
  }

  @Test func reStartAfterStopPlaybackTerminalClearsChatItems() async throws {
    // `.stopAfterLast + .stopPlayback` lands the VM at `.idle` after
    // both sources play. chatItems holds the prior run (3 items).
    // Re-`start()` must wipe chatItems before launching the new
    // playback Task — otherwise the prior run leaks into the new one.
    let sources = try Self.makeTwoSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.stopConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      state == .idle
    }
    #expect(
      viewModel.chatItems.count == 3, "Prior run must hold both demos + boundary")

    viewModel.start()
    // Synchronous post-start: `start()` body wipes chatItems before
    // returning; the newly-spawned playback Task hasn't yielded on
    // this MainActor yet. So the accumulator is observably empty.
    #expect(
      viewModel.chatItems.isEmpty,
      "start() must wipe chatItems before launching playback, got \(viewModel.chatItems)"
    )
  }
}
