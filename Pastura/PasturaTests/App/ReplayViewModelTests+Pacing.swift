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

  /// VM built with `demoDefault` (opts into proportional typing + dwell).
  private static func makeDemoPacedVM() throws -> ReplayViewModel {
    let source = try Self.makeSource()
    return ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
  }

  // The demo fixture is `language: ja` (`makeSource()`), so the run resolves to
  // `.dense` reading density — pin it explicitly here so the next reader does
  // not recompute the expected dwell against `.sparse`.
  private static let demoScript: ReadingScript = .dense

  @Test func floorIsZeroForNonAgentEvent() throws {
    let viewModel = try Self.makeDemoPacedVM()
    #expect(
      viewModel.typingFloorMs(
        for: .roundStarted(round: 1, totalRounds: 3), script: Self.demoScript) == 0)
  }

  @Test func floorIsZeroWhenConfigOptsOut() throws {
    // `fastConfig` leaves `typingCharsPerSecond` nil → no proportional dwell.
    let viewModel = try Self.makeVM()
    let event = SimulationEvent.agentOutput(
      agent: "Alice", output: TurnOutput(fields: ["statement": "Hi."]),
      phaseType: .speakAll)
    #expect(viewModel.typingFloorMs(for: event, script: Self.demoScript) == 0)
  }

  @Test func floorIsTypingPlusReadingDwell() throws {
    let viewModel = try Self.makeDemoPacedVM()  // .normal speed, cps 10
    let event = SimulationEvent.agentOutput(
      agent: "Alice", output: TurnOutput(fields: ["statement": "abc"]),
      phaseType: .speakAll)
    // typingDurationMs("abc", "", 10) == 300 (no punctuation); readingDwell(len 3,
    // dense, normal) == 300 + 60*3 == 480; floor == typing + dwell == 780. The
    // dwell is an absorb beat held AFTER the line types out (the demo reveals the
    // whole line inside the floor window), not max-ed against typing.
    #expect(viewModel.typingFloorMs(for: event, script: Self.demoScript) == 780)
  }

  @Test func floorUsesSparseDwellForLatinScript() throws {
    let viewModel = try Self.makeDemoPacedVM()  // .normal speed, cps 10
    let event = SimulationEvent.agentOutput(
      agent: "Alice", output: TurnOutput(fields: ["statement": "abc"]),
      phaseType: .speakAll)
    // Same typing (300) but sparse dwell == 300 + 38*3 == 414;
    // floor == 300 + 414 == 714. Confirms the dwell tracks the script.
    #expect(viewModel.typingFloorMs(for: event, script: .sparse) == 714)
  }

  @Test func floorOmitsThoughtWhenThoughtsHidden() throws {
    let viewModel = try Self.makeDemoPacedVM()
    viewModel.showAllThoughts = false
    let event = SimulationEvent.agentOutput(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "abc", "inner_thought": "secret"]),
      phaseType: .speakAll)
    // Thought excluded → typing stays 300, floor == 300 + dwell(480) == 780;
    // including it would push typing to 1200 (9 chars + boundary beat) → 1680.
    #expect(viewModel.typingFloorMs(for: event, script: Self.demoScript) == 780)
  }

  // MARK: - introFloorMs (opening-card reveal reservation, #867)

  /// `.demoDefault` opts into typing cps at `.normal`, and the premised source
  /// has a non-empty `scenario.description`, so the opening card reserves a
  /// positive reveal window before the first turn. (Exact value is not pinned —
  /// the `typing + readingDwell` arithmetic is already value-pinned by the
  /// `typingFloorMs` tests above; here only presence-of-a-floor matters.)
  @Test func introFloorIsPositiveForPremiseAtNormalSpeed() throws {
    let source = try Self.makeSourceWithPremise(config: .demoDefault)
    let viewModel = ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
    #expect(viewModel.introFloorMs(forSourceIndex: 0, script: Self.demoScript) > 0)
  }

  /// `.instant` → nil cps → no typing → no reveal floor (symmetric with
  /// `typingFloorMs`'s opt-out path).
  @Test func introFloorIsZeroAtInstantSpeed() throws {
    let source = try Self.makeSourceWithPremise(config: .demoDefault)
    let viewModel = ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
    viewModel.playbackSpeed = .instant
    #expect(viewModel.introFloorMs(forSourceIndex: 0, script: Self.demoScript) == 0)
  }

  /// Empty `scenario.description` → no card → no floor (the default fixture
  /// scenario has `description: ''`).
  @Test func introFloorIsZeroForEmptyDescription() throws {
    let viewModel = try Self.makeDemoPacedVM()
    #expect(viewModel.introFloorMs(forSourceIndex: 0, script: Self.demoScript) == 0)
  }

  /// Whitespace-only `scenario.description` → no card → no floor. Exercises the
  /// *trimmed*-empty predicate (byte-identical to `ScenarioIntroCard.Model.init?`
  /// via the shared `introPremise`), not just the fully-empty branch — so a
  /// hidden card can never leave a phantom pre-first-bubble delay.
  @Test func introFloorIsZeroForWhitespaceOnlyDescription() throws {
    let source = try Self.makeSourceWithPremise(description: "   ", config: .demoDefault)
    let viewModel = ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
    #expect(viewModel.introFloorMs(forSourceIndex: 0, script: Self.demoScript) == 0)
  }

  // MARK: - codePhaseFloorMs (reading reservation for narration lines, #932)

  /// Structured/glanceable code-phase events (votes, scores, eliminations,
  /// pairings) reserve no reading beat — they are covered by the closing card.
  @Test func codePhaseFloorIsZeroForNonTextEvent() throws {
    let viewModel = try Self.makeDemoPacedVM()
    #expect(
      viewModel.codePhaseFloorMs(
        for: .voteResults(votes: [:], tallies: ["Alice": 2]), script: Self.demoScript) == 0)
  }

  /// A text-carrying assignment お題 reserves a pure reading dwell (no typing
  /// term — code-phase lines render instantly). `readingDwell(len 3, dense,
  /// normal) == 480` per `floorIsTypingPlusReadingDwell` above.
  @Test func codePhaseFloorIsReadingDwellForAssignment() throws {
    let viewModel = try Self.makeDemoPacedVM()  // .normal speed, cps 10
    #expect(
      viewModel.codePhaseFloorMs(
        for: .assignment(agent: "Alice", value: "abc"), script: Self.demoScript) == 480)
  }

  /// The shared お題 (`sharedAssignment`, #939) reserves the SAME reading dwell
  /// as the per-agent assignment — it IS the context-critical topic line #932's
  /// dwell exists for. Guards the silent `codePhaseFloorMs` `default: return 0`
  /// gap: a missed `.sharedAssignment` arm would flash the topic too fast.
  @Test func codePhaseFloorIsReadingDwellForSharedAssignment() throws {
    let viewModel = try Self.makeDemoPacedVM()  // .normal speed, cps 10
    #expect(
      viewModel.codePhaseFloorMs(
        for: .sharedAssignment(value: "abc"), script: Self.demoScript) == 480)
  }

  /// `.instant` → nil cps → no reading floor (symmetric with `introFloorMs` /
  /// `typingFloorMs` opt-out).
  @Test func codePhaseFloorIsZeroAtInstantSpeed() throws {
    let viewModel = try Self.makeDemoPacedVM()
    viewModel.playbackSpeed = .instant
    #expect(
      viewModel.codePhaseFloorMs(
        for: .assignment(agent: "Alice", value: "abc"), script: Self.demoScript) == 0)
  }

  /// No text ⇒ no floor: an empty summary and an `eventInjected` miss (`nil`)
  /// both leave no phantom pre-next-event delay.
  @Test func codePhaseFloorIsZeroForEmptyText() throws {
    let viewModel = try Self.makeDemoPacedVM()
    #expect(
      viewModel.codePhaseFloorMs(for: .summary(text: ""), script: Self.demoScript) == 0)
    #expect(
      viewModel.codePhaseFloorMs(
        for: .eventInjected(event: nil), script: Self.demoScript) == 0)
  }

  // MARK: - scaledDelay floor application

  @Test func scaledDelayTakesFloorWhenFloorExceedsBase() throws {
    let viewModel = try Self.makeDemoPacedVM()  // .normal speed (multiplier 1.0)
    // floor 5000 > turnDelayMs 1200 → 5000.
    #expect(viewModel.scaledDelay(for: .turn, floorMs: 5000) == 5000)
  }

  @Test func scaledDelayHonorsRealTimeFloorAtFastSpeed() throws {
    let viewModel = try Self.makeDemoPacedVM()
    viewModel.playbackSpeed = .fast
    // Structural base compresses (1200 / 1.5 == 800) but the floor is real
    // wall-clock time at the current cps, so it is NOT divided → max(800, 5000)
    // == 5000. (The old `max(base, floor)/multiplier` form yielded 3333.)
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

  // MARK: - Cross-consumer drift guard (single source of truth, #835)

  /// Non-tautological guard that the live Sim and the demo replay resolve their
  /// typing cps from the **same** ``PlaybackSpeed/charsPerSecond``. It exercises
  /// the two real consumer methods (not the property directly) at every speed,
  /// so a future re-split — e.g. reintroducing a Sim-only typing-rate property —
  /// diverges one side and trips this. This is the structural protection the cps
  /// unification buys; the value pin lives in `PlaybackSpeedTests`.
  @Test func simAndDemoResolveSameTypingCps() throws {
    let demo = try Self.makeDemoPacedVM()  // .demoDefault opts into typing cps
    let db = try DatabaseManager.inMemory()
    let sim = SimulationViewModel(
      contentFilter: ContentFilter(blockedPatterns: []),
      simulationRepository: GRDBSimulationRepository(dbWriter: db.dbWriter),
      turnRepository: GRDBTurnRepository(dbWriter: db.dbWriter))
    for speed in PlaybackSpeed.allCases {
      demo.playbackSpeed = speed
      sim.speed = speed
      #expect(
        demo.typingCharsPerSecond == sim.effectiveCharsPerSecond(forEntryId: UUID()),
        "sim and demo typing cps diverged at \(speed)")
    }
  }
}
