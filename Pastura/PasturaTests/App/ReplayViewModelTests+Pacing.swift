import Foundation
import Testing

@testable import Pastura

/// Pacing-floor (proportional turn dwell) tests for ``ReplayViewModel``.
///
/// Sibling extension of `ReplayViewModelTests` (NOT a new `@Suite`) per
/// `.claude/rules/testing.md` — a separate suite would run in parallel and
/// race the VM-spawning original on the shared test process.
extension ReplayViewModelTests {

  // MARK: - typingCharsPerSecond accessor (single source of truth)

  @Test func typingCharsPerSecondForwardsConfigNil() throws {
    // `fastConfig` leaves `typingCharsPerSecond` at its `nil` default.
    let viewModel = try Self.makeVM()
    #expect(viewModel.typingCharsPerSecond == nil)
  }

  @Test func typingCharsPerSecondForwardsConfigValue() throws {
    let source = try Self.makeSource()
    let viewModel = ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
    #expect(viewModel.typingCharsPerSecond == PlaybackSpeed.normal.charsPerSecond)
  }

  // MARK: - showAllThoughts ownership (moved from host @State)

  @Test func showAllThoughtsDefaultsToTrue() throws {
    let viewModel = try Self.makeVM()
    #expect(viewModel.showAllThoughts)
  }

  // MARK: - typingFloorMs (per-bubble dwell floor)

  /// VM built with `demoDefault` (opts into `typingCharsPerSecond == 30`).
  private static func makeDemoPacedVM() throws -> ReplayViewModel {
    let source = try Self.makeSource()
    return ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
  }

  @Test func floorIsZeroForNonAgentEvent() throws {
    let viewModel = try Self.makeDemoPacedVM()
    #expect(viewModel.typingFloorMs(for: .roundStarted(round: 1, totalRounds: 3)) == 0)
  }

  @Test func floorIsZeroWhenConfigOptsOut() throws {
    // `fastConfig` leaves `typingCharsPerSecond` nil → no proportional dwell.
    let viewModel = try Self.makeVM()
    let event = SimulationEvent.agentOutput(
      agent: "Alice", output: TurnOutput(fields: ["statement": "Hi."]),
      phaseType: .speakAll)
    #expect(viewModel.typingFloorMs(for: event) == 0)
  }

  @Test func floorIsTypingDurationPlusReadPause() throws {
    let viewModel = try Self.makeDemoPacedVM()
    let event = SimulationEvent.agentOutput(
      agent: "Alice", output: TurnOutput(fields: ["statement": "Hi."]),
      phaseType: .speakAll)
    // typingDurationMs("Hi.", "", 30) == 400; + typingReadPauseMs(700) == 1100.
    #expect(viewModel.typingFloorMs(for: event) == 1100)
  }

  @Test func floorOmitsThoughtWhenThoughtsHidden() throws {
    let viewModel = try Self.makeDemoPacedVM()
    viewModel.showAllThoughts = false
    let event = SimulationEvent.agentOutput(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "Hi.", "inner_thought": "secret"]),
      phaseType: .speakAll)
    // Thought segment excluded → same as the no-thought case (1100), not larger.
    #expect(viewModel.typingFloorMs(for: event) == 1100)
  }

  // MARK: - scaledDelay floor application

  @Test func scaledDelayTakesFloorWhenFloorExceedsBase() throws {
    let viewModel = try Self.makeDemoPacedVM()  // .normal speed (multiplier 1.0)
    // floor 5000 > turnDelayMs 1200 → 5000.
    #expect(viewModel.scaledDelay(for: .turn, floorMs: 5000) == 5000)
  }

  @Test func scaledDelayTakesBaseWhenFloorBelowBase() throws {
    let viewModel = try Self.makeDemoPacedVM()
    // floor 100 < turnDelayMs 1200 → 1200 (short turns keep the ~1.2s rhythm).
    #expect(viewModel.scaledDelay(for: .turn, floorMs: 100) == 1200)
  }

  @Test func scaledDelayAppliesFloorToLifecycleKind() throws {
    let viewModel = try Self.makeDemoPacedVM()
    // Lifecycle base is 0, so the floor (a preceding bubble still typing) wins.
    #expect(viewModel.scaledDelay(for: .lifecycle, floorMs: 800) == 800)
  }

  @Test func instantSpeedCollapsesDelayIncludingFloor() throws {
    let viewModel = try Self.makeDemoPacedVM()
    viewModel.playbackSpeed = .instant
    #expect(viewModel.scaledDelay(for: .turn, floorMs: 5000) == 0)
  }
}
