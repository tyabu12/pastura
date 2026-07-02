import Foundation
import Testing

@testable import Pastura

// Closing-card (`ChatItem.simulationResult`) emission tests for
// `ReplayViewModel` (#884) — the demo mirror of the live sim's final-ranking
// card (#868). Sibling-file `extension` per `.claude/rules/testing.md` — NOT a
// new `@Suite` (a parallel suite would race the VM-spawning original on the
// shared test process; the `.serialized` / `.timeLimit` traits live on the base
// `@Suite`).
extension ReplayViewModelTests {

  // MARK: - Ranking-outcome fixtures

  /// A demo YAML that pairs one turn with a `scoreUpdate` code-phase event so
  /// the source resolves to a `.ranking` closing card. The score event shares
  /// the turn's `(round, phase_index)` so it synthesises no extra
  /// `.phaseStarted` marker — keeping this fixture off any phase-count canary.
  static let rankingResultYAML = """
    schema_version: 1
    turns:
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hello' }
    code_phase_events:
      - round: 1
        phase_index: 0
        phase_type: score_calc
        summary: 'Scores — Alice: 5, Bob: 2'
        payload:
          kind: scoreUpdate
          scores:
            Alice: 5
            Bob: 2
    """

  /// A source (Alice/Bob `speak_all` scenario) whose recorded events include a
  /// non-zero `scoreUpdate` — so `concludeSource` resolves a `.ranking` card.
  static func makeRankingSource(config: ReplayPlaybackConfig) throws -> YAMLReplaySource {
    try YAMLReplaySource(
      yaml: rankingResultYAML, scenario: makeScenario(), config: config)
  }

  /// True when `chatItems` holds at least one closing card.
  static func hasResultCard(_ viewModel: ReplayViewModel) -> Bool {
    viewModel.chatItems.contains {
      if case .simulationResult = $0 { return true }
      return false
    }
  }

  // MARK: - Segment-tail emission

  /// A source with a resolvable outcome appends a `.simulationResult` closing
  /// card as the tail chat item, carrying the resolved ranking Model. Uses
  /// `holdConfig` (stopAfterLast + awaitTransitionSignal) so the VM holds after
  /// the single source's plan, and `.loop`-only wrap-hold never fires.
  @Test func concludeAppendsRankingResultCardAtTail() async throws {
    let source = try Self.makeRankingSource(config: Self.holdConfig)
    let viewModel = ReplayViewModel(
      sources: [source], config: Self.holdConfig, contentFilter: ContentFilter())
    viewModel.start()
    // The card is appended by `concludeSource` AFTER the plan drains, so poll on
    // `chatItems` (reading state cursor would race the append).
    await Self.waitForState(viewModel, timeout: .seconds(5)) { _ in
      Self.hasResultCard(viewModel)
    }
    guard case .simulationResult(_, let model) = viewModel.chatItems.last else {
      Issue.record(
        "chatItems.last expected .simulationResult, got \(String(describing: viewModel.chatItems.last))"
      )
      return
    }
    #expect(model.framing == .ranking)
    #expect(model.entries.count == 2)
    #expect(model.entries.first?.name == "Alice")
    #expect(model.entries.first?.rank == 1)
    #expect(model.entries.first?.primaryValue == 5)
    #expect(model.entries.last?.name == "Bob")
    #expect(model.entries.last?.rank == 2)
  }

  /// A summary-only source (no scores / votes / eliminations) resolves to `nil`
  /// and appends NO closing card — mirroring the resolver's visibility guard
  /// and the intro card's empty-premise skip. Uses the default `speak_all`
  /// fixture, which carries no `code_phase_events`.
  @Test func summaryOnlySourceAppendsNoResultCard() async throws {
    let viewModel = try Self.makeVM()  // default: speak_all only, no code events
    viewModel.start()
    // Wait for the plan to drain (3 turns + 2 lifecycle = 5), then give
    // `concludeSource` a beat to run before asserting absence.
    await Self.waitForState(viewModel, timeout: .seconds(5)) { state in
      if case .playing(_, let cursor) = state { return cursor >= 5 }
      return false
    }
    try await Task.sleep(for: .milliseconds(50))
    #expect(!Self.hasResultCard(viewModel))
  }

  // MARK: - Rotation ordering (result card → boundary)

  /// On mid-cycle rotation the closing card is the tail of the FINISHING
  /// segment — it lands before the `.demoBoundary` that opens the next segment
  /// (on-screen order: … turns, result card, boundary, next intro …).
  @Test func resultCardPrecedesBoundaryOnRotation() async throws {
    let sources = [
      try Self.makeRankingSource(config: Self.holdConfig),
      try Self.makeRankingSource(config: Self.holdConfig)
    ]
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.holdConfig, contentFilter: ContentFilter())
    viewModel.start()
    // Wait until BOTH sources have concluded (2 closing cards present). Polling
    // the card count — not the state cursor — avoids racing the append, which
    // lands just after `playSource` sets the final `.playing(1, 4)` cursor.
    await Self.waitForState(viewModel, timeout: .seconds(6)) { _ in
      viewModel.chatItems.filter {
        if case .simulationResult = $0 { return true }
        return false
      }.count >= 2
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
    // The item immediately before the boundary is source 0's closing card.
    guard boundaryIndex >= 1 else {
      Issue.record("No item before the boundary at \(boundaryIndex): \(viewModel.chatItems)")
      return
    }
    if case .simulationResult = viewModel.chatItems[boundaryIndex - 1] {
      // expected
    } else {
      Issue.record(
        "Item before boundary expected .simulationResult, got \(viewModel.chatItems[boundaryIndex - 1])"
      )
    }
    // Source 1's own closing card is the very last item.
    if case .simulationResult = viewModel.chatItems.last {
      // expected
    } else {
      Issue.record(
        "chatItems.last expected source-1 .simulationResult, got \(String(describing: viewModel.chatItems.last))"
      )
    }
  }

  // MARK: - Loop re-arm (Critical guard, #884)

  /// The append latch must clear on every fresh source entry, so a source
  /// re-appends its closing card on each `.loop` cycle. Guards the
  /// keyed-`Set<Int>`-never-cleared bug (cards would render for cycle 1 only,
  /// then silently vanish under the default loop-forever demo config).
  @Test func loopReArmsResultCardEachCycle() async throws {
    let sources = [
      try Self.makeRankingSource(config: Self.loopConfig),
      try Self.makeRankingSource(config: Self.loopConfig)
    ]
    let viewModel = ReplayViewModel(
      sources: sources, config: Self.loopConfig, contentFilter: ContentFilter())
    viewModel.start()
    // Step 1: wait for wrap-around — the VM must reach source 1, then return to
    // source 0. The wrap wipes `chatItems`, so any card seen after this point
    // belongs to cycle 2.
    var sawSource1 = false
    await Self.waitForState(viewModel, timeout: .seconds(8)) { state in
      guard case .playing(let idx, _) = state else { return false }
      if idx == 1 { sawSource1 = true }
      return sawSource1 && idx == 0
    }
    guard sawSource1 else {
      Issue.record("Never observed source 1 before timeout; state=\(viewModel.state)")
      return
    }
    // Step 2: source 0 replays in cycle 2 and must append its card AGAIN. If the
    // latch were keyed and never cleared, no card would appear this cycle.
    await Self.waitForState(viewModel, timeout: .seconds(8)) { _ in
      Self.hasResultCard(viewModel)
    }
    #expect(Self.hasResultCard(viewModel), "closing card must re-arm on the second loop cycle")
    viewModel.downloadComplete()  // stop the infinite loop deterministically
  }
}
