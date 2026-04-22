import Foundation
import Testing

@testable import Pastura

/// End-to-end integration: `BundledDemoReplaySource.loadFromYAMLs` →
/// `ReplayViewModel` → observed state sequence.
///
/// Exercises the composition of PR1's new types against hand-written
/// fixture YAMLs shaped like the real demo-replay schema. Complements
/// the unit suites (which cover each type in isolation) by asserting
/// that wiring them together produces the expected visible behaviour:
/// lifecycle events get synthesised, ContentFilter is applied at the
/// VM layer, source rotation happens, and the paused→resumed path
/// lands on the right cursor.
///
/// `.serialized` per `.claude/rules/testing.md` — VM spawns playback
/// tasks; a parallel runner could cleanup-race against this suite.
@Suite("DemoReplayIntegration", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct DemoReplayIntegrationTests {

  // MARK: - Fixtures

  static let wordWolfPresetYAML = """
    id: word_wolf
    name: Word Wolf
    description: ''
    agents: 3
    rounds: 1
    context: ''
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
      - name: Carol
        description: ''
    phases:
      - type: speak_all
        prompt: say
        output:
          statement: string
    """

  static let prisonersDilemmaPresetYAML = """
    id: prisoners_dilemma
    name: Prisoner's Dilemma
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
        prompt: choose
        output:
          statement: string
    """

  static func wordWolfDemoYAML() -> String {
    let sha = ReplayHashing.sha256Hex(wordWolfPresetYAML)
    return """
      schema_version: 1
      preset_ref:
        id: word_wolf
        yaml_sha256: \(sha)
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'I think the word is cat' }
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'shit I disagree' }
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Carol
          fields: { statement: 'let me think' }
      """
  }

  static func prisonersDilemmaDemoYAML() -> String {
    let sha = ReplayHashing.sha256Hex(prisonersDilemmaPresetYAML)
    return """
      schema_version: 1
      preset_ref:
        id: prisoners_dilemma
        yaml_sha256: \(sha)
      turns:
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Alice
          fields: { statement: 'cooperate' }
        - round: 1
          phase_index: 0
          phase_type: speak_all
          agent: Bob
          fields: { statement: 'defect' }
      """
  }

  struct MultiPresetResolver: PresetResolver {
    let presets: [String: String]

    func resolvePreset(id: String) throws -> ResolvedPreset? {
      guard let yaml = presets[id] else { return nil }
      let scenario = try ScenarioLoader().load(yaml: yaml)
      return ResolvedPreset(scenario: scenario, sha256: ReplayHashing.sha256Hex(yaml))
    }
  }

  static let resolver = MultiPresetResolver(presets: [
    "word_wolf": wordWolfPresetYAML,
    "prisoners_dilemma": prisonersDilemmaPresetYAML
  ])

  /// Single-pass config: `.stopAfterLast + .awaitTransitionSignal` so
  /// the test observes a deterministic end state (both demos played
  /// once, VM holds at `.playing(1, lastCursor)`). Fixture size
  /// bounded to ~ 5 events per demo × 2 demos = 10 events total,
  /// well under the 20-event cap from the plan.
  static let integrationConfig = ReplayPlaybackConfig(
    speedMultiplier: 100.0,
    turnDelayMs: 20,
    codePhaseDelayMs: 5,
    loopBehaviour: .stopAfterLast,
    onComplete: .awaitTransitionSignal)

  static func makeSources() -> [BundledDemoReplaySource] {
    let yamls = [
      (name: "word_wolf_demo", contents: wordWolfDemoYAML()),
      (name: "prisoners_dilemma_demo", contents: prisonersDilemmaDemoYAML())
    ]
    return BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: integrationConfig)
  }

  static func waitForState(
    _ viewModel: ReplayViewModel, timeout: Duration = .seconds(5),
    predicate: @MainActor (ReplayViewModel.State) -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if predicate(viewModel.state) { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  // MARK: - Integration tests

  @Test func bothDemosLoadSuccessfullyFromFixtures() throws {
    let sources = Self.makeSources()
    #expect(sources.count == 2)
    #expect(sources[0].scenario.id == "word_wolf")
    #expect(sources[1].scenario.id == "prisoners_dilemma")
  }

  @Test func endToEndPlaysAllDemosInOrder() async throws {
    let sources = Self.makeSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.integrationConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // With `.stopAfterLast + .awaitTransitionSignal`, the VM should
    // play source 0 (3 turns), rotate to source 1 (2 turns), then
    // hold at `.playing(1, 4)` (2 lifecycle + 2 turns for source 1).
    await Self.waitForState(viewModel) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 4 {
        return true
      }
      return false
    }
    if case .playing(let idx, _) = viewModel.state {
      #expect(idx == 1, "Expected to land on source 1 after rotation")
    } else {
      Issue.record("Expected held .playing(1, _), got \(viewModel.state)")
    }
    // Source 1's final agentOutputs should only reflect its own
    // turns — source 0's were cleared by `resetPerDemoState()`.
    #expect(viewModel.agentOutputs.count == 2)
    #expect(viewModel.agentOutputs[0].agent == "Alice")
    #expect(viewModel.agentOutputs[1].agent == "Bob")
  }

  @Test func contentFilterAppliedToAgentOutputsThroughFullPipeline() async throws {
    // Single-demo VM: avoids rotation resetting `agentOutputs` while
    // we're trying to read Bob's turn. Uses the word_wolf fixture
    // whose second turn contains a blocklist substring ("shit").
    let yamls = [
      (name: "ww", contents: Self.wordWolfDemoYAML())
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: Self.resolver, config: Self.integrationConfig)
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.integrationConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Word_wolf has 3 turns. `.stopAfterLast + .awaitTransitionSignal`
    // + single source means the VM holds at `.playing(0, 5)` (2
    // lifecycle + 3 turns) without rotating.
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count == 3 }
    let bobOutput = viewModel.agentOutputs[1].output.statement ?? ""
    #expect(!bobOutput.lowercased().contains("shit"))
    #expect(bobOutput.contains("***"))
    // Persona names pass through untouched (narrow-scope invariant).
    #expect(viewModel.agentOutputs[1].agent == "Bob")
  }

  @Test func downloadCompleteMidPlaybackTransitionsCleanly() async throws {
    let sources = Self.makeSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.integrationConfig,
      contentFilter: ContentFilter())
    viewModel.start()
    // Wait until at least the first source has started publishing,
    // so we exercise the "transition from mid-playback" path rather
    // than the "transition from idle" no-op.
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
  }

  @Test func startThenPauseResumeThenDownloadComplete() async throws {
    // Drives the full DemoReplayHostView lifecycle chain end-to-end across
    // ≥ 2 sources: start → some outputs → background → assert .paused →
    // foreground → assert .playing → downloadComplete → assert .transitioning.
    let sources = Self.makeSources()
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.integrationConfig,
      contentFilter: ContentFilter())
    viewModel.start()

    // Wait until at least one agent output so playback is in-flight.
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }

    viewModel.onBackground()
    guard case .paused(let pausedIdx, let pausedCursor, _) = viewModel.state else {
      Issue.record("Expected .paused after onBackground(), got \(viewModel.state)")
      return
    }

    viewModel.onForeground()
    // Resume synchronously restores .playing at the same position.
    if case .playing(let rIdx, let rCursor) = viewModel.state {
      #expect(rIdx == pausedIdx)
      #expect(rCursor == pausedCursor)
    } else {
      Issue.record("Expected .playing after onForeground(), got \(viewModel.state)")
      return
    }

    // Simulate download completing while playback is running.
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
  }

  @Test func pauseAndResumeLandsOnSameCursor() async throws {
    // Slower pacing so the pause catches mid-sleep — otherwise 100×
    // collapses the sleep to 0 and we observe a boundary pause that
    // happens to have remainingDelayMs == 0.
    let slowConfig = ReplayPlaybackConfig(
      speedMultiplier: 1.0, turnDelayMs: 150, codePhaseDelayMs: 50,
      loopBehaviour: .stopAfterLast, onComplete: .awaitTransitionSignal)
    let yamls = [
      (name: "ww", contents: Self.wordWolfDemoYAML())
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: Self.resolver, config: slowConfig)
    let viewModel = ReplayViewModel(
      sources: sources, config: slowConfig, contentFilter: ContentFilter())
    viewModel.start()
    // Wait for at least one agent output, then pause.
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.onBackground()
    guard case .paused(let sourceIndex, let cursor, _) = viewModel.state else {
      Issue.record("Expected .paused after onBackground, got \(viewModel.state)")
      return
    }
    let pausedOutputs = viewModel.agentOutputs.count
    viewModel.onForeground()
    // Resume from same position — state returns to .playing at the
    // captured (sourceIndex, cursor).
    if case .playing(let rIdx, let rCursor) = viewModel.state {
      #expect(rIdx == sourceIndex)
      #expect(rCursor == cursor)
    } else {
      Issue.record("Expected .playing after onForeground, got \(viewModel.state)")
    }
    // Playback eventually completes the remaining 2 turns (word_wolf
    // has 3 total). Final agentOutputs should be 3.
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count == 3 }
    #expect(viewModel.agentOutputs.count >= pausedOutputs)
  }
}
