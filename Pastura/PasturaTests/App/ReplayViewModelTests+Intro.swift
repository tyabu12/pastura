import Foundation
import Testing

@testable import Pastura

// Opening-card (`ChatItem.scenarioIntro`) emission tests for `ReplayViewModel`
// (#867). Sibling-file extension per `.claude/rules/testing.md` — NOT a new
// `@Suite` (a parallel suite would race the VM-spawning original on the shared
// test process).
//
// The premised-scenario helpers below are `internal static` (not `private`) so
// the sibling `ReplayViewModelTests+Pacing.swift` can build a source whose
// `scenario.description` is non-empty for the `introFloorMs` tests — the default
// suite fixtures all use `description: ''`.
extension ReplayViewModelTests {

  // MARK: - Premised-scenario fixtures

  /// Non-empty premise for the source-0 opening card. `ja` text so the source
  /// resolves to the `.dense` reading-density class (matches `demoScript`).
  static let introPremiseText = "五人の参加者から少数派を会話で見抜く推理ゲーム。"

  /// Second-source premise, distinct from ``introPremiseText`` so a rotation
  /// test can assert *which* intro card follows the boundary marker.
  static let introPremiseTextTwo = "全員が同じお題で言い訳を重ねるターン制コメディ。"

  /// A single-phase `speak_all` scenario (2 personas, `ja`) with a caller-chosen
  /// `description`. Used to exercise the opening card, which reads
  /// `scenario.description` as its premise.
  static func makeScenarioWithPremise(description: String) throws -> Scenario {
    let yaml = """
      id: premised
      language: ja
      name: Premised Demo
      description: '\(description)'
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
    return try ScenarioLoader().load(yaml: yaml)
  }

  /// A demo source (the shared `threeTurnYAML` turns) whose backing scenario
  /// carries `description` — so its opening card is shown.
  static func makeSourceWithPremise(
    description: String = introPremiseText, config: ReplayPlaybackConfig
  ) throws -> YAMLReplaySource {
    try YAMLReplaySource(
      yaml: threeTurnYAML,
      scenario: makeScenarioWithPremise(description: description),
      config: config)
  }

  /// Two single-turn demo sources with distinct premises, for rotation-order
  /// assertions. Mirrors `makeTwoSources()` but with non-empty descriptions.
  static func makeTwoPremisedSources(config: ReplayPlaybackConfig) throws
    -> [YAMLReplaySource] {
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
    return [
      try YAMLReplaySource(
        yaml: yaml1,
        scenario: makeScenarioWithPremise(description: introPremiseText),
        config: config),
      try YAMLReplaySource(
        yaml: yaml2,
        scenario: makeScenarioWithPremise(description: introPremiseTextTwo),
        config: config)
    ]
  }

  // MARK: - start() emission

  /// A premised source prepends its opening card as the first chat item. The
  /// append happens synchronously inside `start()` (before the playback `Task`
  /// runs), so the assertion is race-free without awaiting.
  @Test func startPrependsScenarioIntroForPremisedSource() throws {
    let source = try Self.makeSourceWithPremise(config: .demoDefault)
    let viewModel = ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
    viewModel.start()
    guard case .scenarioIntro(_, let premise) = viewModel.chatItems.first else {
      Issue.record(
        "chatItems.first expected .scenarioIntro, got \(String(describing: viewModel.chatItems.first))"
      )
      return
    }
    #expect(premise == Self.introPremiseText)
  }

  /// An empty-description source inserts NO opening card — mirrors the card's
  /// own `Model.init?` visibility guard. Asserted synchronously after `start()`
  /// (the empty-desc default fixture; the playback `Task` has not run yet).
  @Test func startInsertsNoIntroForEmptyDescription() throws {
    let viewModel = try Self.makeVM()  // default fixture: `description: ''`
    viewModel.start()
    let hasIntro = viewModel.chatItems.contains {
      if case .scenarioIntro = $0 { return true }
      return false
    }
    #expect(!hasIntro)
  }

  // MARK: - Rotation emission (boundary → intro order)

  /// On rotation the opening card follows the demo-boundary marker (order is
  /// always boundary → intro card), and carries the *next* source's premise.
  /// Uses `stopAfterLast + awaitTransitionSignal` so the VM holds after a
  /// deterministic source-0 → source-1 transition.
  @Test func rotationInsertsIntroAfterBoundary() async throws {
    let sources = try Self.makeTwoPremisedSources(config: Self.holdConfig)
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.holdConfig, contentFilter: ContentFilter())
    viewModel.start()
    // Hold point: source 1 reached its final cursor (2 lifecycle + 1 turn).
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(let idx, let cursor) = state, idx == 1, cursor >= 3 {
        return true
      }
      return false
    }
    guard
      let boundaryIndex = viewModel.chatItems.firstIndex(where: {
        if case .demoBoundary = $0 { return true }
        return false
      })
    else {
      Issue.record("Expected a .demoBoundary in chatItems, got \(viewModel.chatItems)")
      return
    }
    // The item immediately after the boundary is source 1's opening card.
    let afterBoundary = viewModel.chatItems[boundaryIndex + 1]
    guard case .scenarioIntro(_, let premise) = afterBoundary else {
      Issue.record("chatItems after boundary expected .scenarioIntro, got \(afterBoundary)")
      return
    }
    #expect(premise == Self.introPremiseTextTwo)
    // Source 0's card is still the very first item (accumulate-across-rotation).
    if case .scenarioIntro(_, let firstPremise) = viewModel.chatItems.first {
      #expect(firstPremise == Self.introPremiseText)
    } else {
      Issue.record(
        "chatItems.first expected source-0 .scenarioIntro, got \(String(describing: viewModel.chatItems.first))"
      )
    }
  }
}
