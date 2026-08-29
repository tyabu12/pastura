import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

/// `.serialized` because every emitter case constructs a `SimulationRunner`,
/// which spawns `Task` + `AsyncStream` — the shape
/// `.claude/rules/swift-testing-parallelism.md` says to serialize.
///
/// **The mitigation is intra-suite only, and the residual is real.** That rule
/// also says separate top-level suites still run concurrently, and
/// `HarnessRunnerTests` / `HarnessLanguageDetectorTests` construct the same
/// types in this target without `.serialized`. CI runs a bare `swift test` with
/// no `--no-parallel`, so cross-suite overlap is unaddressed here — this
/// annotation reduces the exposure, it does not remove it. Recorded rather than
/// glossed: a comment that names a hazard and implies it is handled is worse
/// than none. Closing it means `--no-parallel` in CI (a separate change, since
/// it slows every suite) or merging the runner-constructing suites.
///
/// Paths in these cases resolve against the current directory, so the suite
/// must run from the repository root — the same contract the CLI documents.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ParityFixtureEmitterTests {

  // MARK: - Choice-option derivation

  @Test("two distinct choose menus are rejected rather than silently halved")
  func choiceOptionDerivationRejectsAmbiguity() throws {
    // The responder reads the schema and nothing else, so it cannot tell which
    // `choose` phase is calling. Picking either menu would answer the other
    // phase off-menu and drop every one of its pairings — a fixture that runs
    // and scores nothing. Generation-time failure is the honest outcome.
    let scenario = makeScenario(phases: [
      Phase(type: .choose, options: ["cooperate", "betray"]),
      Phase(
        type: .conditional, condition: "round >= 1",
        thenPhases: [Phase(type: .choose, options: ["rock", "paper"])])
    ])

    #expect(throws: ParityFixtureError.self) {
      _ = try ParityFixtureEmitter.choiceOptions(in: scenario)
    }
  }

  @Test("a repeated menu, including one nested in a branch, is not ambiguity")
  func choiceOptionDerivationAcceptsARepeatedMenu() throws {
    // The guard is on DISTINCT menus: a scenario reusing one menu across a
    // top-level phase and a conditional branch has a single right answer, and
    // rejecting it would rule out a shape nothing forbids. This also pins that
    // the walk descends into `elsePhases`, which the ambiguity case above would
    // pass even if it did not.
    let scenario = makeScenario(phases: [
      Phase(type: .choose, options: ["cooperate", "betray"]),
      Phase(
        type: .conditional, condition: "round >= 1",
        elsePhases: [Phase(type: .choose, options: ["cooperate", "betray"])])
    ])

    #expect(try ParityFixtureEmitter.choiceOptions(in: scenario) == ["cooperate", "betray"])
  }

  @Test("a scenario with no choose phase derives an empty menu")
  func choiceOptionDerivationIsEmptyWithoutAChoosePhase() throws {
    // The fallback branch every non-`choose` fixture takes — the two
    // `target_score_race` fixtures, `boketeNominal`, `iiwakeBattleNominal` and
    // the structural control are its live users.
    let scenario = makeScenario(phases: [Phase(type: .speakAll, prompt: "hi")])

    #expect(try ParityFixtureEmitter.choiceOptions(in: scenario).isEmpty)
  }

  /// A minimal scenario carrying only the phases under test — the derivation
  /// reads nothing else.
  private func makeScenario(phases: [Phase]) -> Scenario {
    Scenario(
      id: "derivation-probe", name: "probe", description: "probe", language: "en",
      agentCount: 0, rounds: 1, context: "probe", personas: [], phases: phases)
  }

  // MARK: - Determinism

  // The three cases below run over EVERY spec rather than `specs.first`: they
  // are properties of the emitter, so a sample only ever proved them of
  // whichever fixture happened to be declared first — and this file already
  // records one such defect surviving in the unscoped sibling (see
  // `everyFixtureExercisesVotingNotJustItsShape`).

  @Test("two runs of the same spec produce byte-identical fixtures")
  func emitterIsDeterministic() async throws {
    #expect(!ParityFixtureEmitter.specs.isEmpty, "no fixture specs declared")
    for spec in ParityFixtureEmitter.specs {
      let first = try await ParityFixtureEmitter.run(spec)
      let second = try await ParityFixtureEmitter.run(spec)

      // The reason this can pass at all: `EventLineMapper` takes `t` / `attempt`
      // as parameters, and `ParityFixtureEmitter.normalize` zeroes the one
      // measured quantity a payload carries. Remove either and this reddens —
      // `inferenceCompleted.durationSeconds` was observed varying per call before
      // the normalization landed.
      #expect(first == second, "\(spec.name)")
    }
  }

  @Test("no transcript line carries a measured duration")
  func transcriptCarriesNoMeasuredDuration() async throws {
    #expect(!ParityFixtureEmitter.specs.isEmpty, "no fixture specs declared")
    for spec in ParityFixtureEmitter.specs {
      let fixture = try await ParityFixtureEmitter.run(spec)

      // Asserted on the value, not on the key's absence: the key is legitimately
      // present, and a check for absence would pass for the wrong reason if the
      // event stopped being emitted at all.
      let durations = fixture.transcript.filter { $0.contains("\"duration_seconds\"") }
      #expect(
        !durations.isEmpty,
        "\(spec.name): no inference_completed line — the assertion below would be vacuous")
      #expect(durations.allSatisfy { $0.contains("\"duration_seconds\":0") }, "\(spec.name)")
    }
  }

  @Test("the run drives the engine end to end")
  func emitterProducesACompleteRun() async throws {
    #expect(!ParityFixtureEmitter.specs.isEmpty, "no fixture specs declared")
    for spec in ParityFixtureEmitter.specs {
      let fixture = try await ParityFixtureEmitter.run(spec)

      // `callCount` includes suspend re-issues (`RecordingResponder`), so the
      // equality only holds once the spec's own scheduled suspends are added
      // back in — 0 for every spec but `paritySuspendPreservesRetryBudget`.
      let scheduledSuspends = spec.suspendBeforeResponse.values.reduce(0, +)
      #expect(
        fixture.callCount == fixture.responses.count + scheduledSuspends, "\(spec.name)")
      // "End to end" means *reaching its own terminal event*, which is not the
      // same event for every spec: a cancelling fixture ends at
      // `error cancelled` by construction, and asserting `simulation_completed`
      // for it would demand the run keep going past the cut it exists to
      // freeze. Both arms are asserted, so neither spec kind gets a pass —
      // `ParityFixtureEmitterTests+Cancel.swift` then pins the cancelled tail
      // in detail.
      let terminal =
        spec.cancelAfterPhaseCompleted == nil
        ? "\"simulation_completed\"" : "\"error\":\"cancelled\""
      #expect(fixture.transcript.contains { $0.contains(terminal) }, "\(spec.name)")
      // Keyed on the spec's own scenario path rather than a hard-coded preset
      // id, which was only ever true of the two `target_score_race` fixtures.
      // `#require`, not `?? ""`: `String.contains("")` is `true`, so an empty
      // fallback would pass vacuously.
      let basename = try #require(spec.scenarioPath.split(separator: "/").last)
      let scenarioId = basename.replacingOccurrences(of: ".yaml", with: "")
      #expect(fixture.scenarioJSON.contains(scenarioId), "\(spec.name): expected id \(scenarioId)")
    }
  }

  @Test("no run emits a language mismatch")
  func parityRunEmitsNoLanguageMismatch() async throws {
    // Guards the deliberate `detector:` omission in `ParityFixtureEmitter.run`.
    // `HarnessLanguageDetector` wraps an OS-version-dependent classifier, and
    // the responder answers a `ja` scenario with ASCII — so an injected detector
    // would trip ADR-010 retries, change `callCount`, and make the golden vary
    // by host.
    //
    // **Be precise about what this proves.** With no detector wired, zero
    // `language_mismatch` events is true *by construction*, so this passes today
    // for a reason that has nothing to do with the assertion. It is an omission
    // guard: it reddens if a detector is re-added AND fires. It deliberately has
    // no positive control, because the only one available — running with a real
    // detector and asserting a mismatch appears — would depend on the same OS
    // classifier this omission exists to keep out of the golden.

    for spec in ParityFixtureEmitter.specs {
      let fixture = try await ParityFixtureEmitter.run(spec)
      #expect(!fixture.transcript.contains { $0.contains("language_mismatch") }, "\(spec.name)")
    }
  }

  // MARK: - The negative-control fixture

  @Test("the divergent spec's hand-pinned override indices still land on one turn")
  func divergentSpecOverridesStayAligned() async throws {
    // The negative control's contract is index-pinned: calls 0-2 are ONE agent's
    // speak_all turn across the whole retry window, and call 3 is the next turn.
    // That holds only while the retry budget is 3 and speak_all is phase 0.
    // Change either and the overrides silently land on different turns — the
    // emitter still succeeds and `--check` merely asks for a regeneration, after
    // which the fixture drives a different divergence than its own KDoc claims.
    // Nothing else on the Swift side reddens, so these two assertions are it.
    // Selected BY NAME, not by position: `specs.last` used to be the divergent
    // spec and silently became `parityStructuralControl` when a third fixture
    // was appended, so the assertions below measured the wrong pair and failed
    // for a reason unrelated to their subject.
    guard
      let nominal = ParityFixtureEmitter.specs.first(where: { $0.name == "targetScoreRaceNominal" }
      ),
      let divergent = ParityFixtureEmitter.specs.first(where: {
        $0.name == "targetScoreRaceDivergent"
      })
    else {
      Issue.record("expected the nominal and divergent specs to exist by name")
      return
    }
    let nominalRun = try await ParityFixtureEmitter.run(nominal)
    let divergentRun = try await ParityFixtureEmitter.run(divergent)

    // Exactly two extra attempts — which is what makes calls 0-2 a single turn.
    // Reddens on a retry-budget change.
    #expect(divergentRun.callCount == nominalRun.callCount + 2)
    // `#require`, not `#expect`: a bare expectation does not halt, so a shorter
    // list would trap on the subscripts below and kill the whole test process —
    // taking every other suite's results with it — instead of failing this case.
    // A structural change is precisely what this test exists to catch.
    try #require(divergentRun.responses.count > 4)
    try #require(nominalRun.responses.count > 3)
    #expect(divergentRun.responses[3].contains("confidence"))
    #expect(divergentRun.transcript.contains { $0.contains("\"confidence\":\"1\"") })
    // Phase order, which the two assertions above do NOT defend: the override is
    // applied at call index 3 whatever phase that is, and an unexpected key
    // survives into `agent_output` regardless of schema. These key on the
    // *derived* neighbours' schemas instead, so either reddens if `speak_all`
    // stops being phase 0.
    #expect(
      nominalRun.responses[3].contains("\"vote\""), "call 3 should be the nominal run's first vote")
    #expect(
      divergentRun.responses[4].contains("\"statement\""),
      "call 4 should still be a speak_all turn once the retry window shifts it")
  }

  // MARK: - Raw-string safety guard

  @Test("a payload Kotlin would interpolate is rejected at generation time")
  func rawStringGuardRejectsInterpolation() throws {
    // Negative control: the guard's success path proves nothing, so construct
    // the thing it claims to catch and confirm it fires.
    let unsafe = ParityFixtureEmitter.Fixture(
      name: "unsafe", purpose: "control", scenarioJSON: #"{"id": "$injected"}"#,
      responses: [], transcript: [], callCount: 0)

    #expect(throws: ParityFixtureError.self) {
      _ = try ParityFixtureEmitter.kotlinSource(from: [unsafe])
    }
  }

  @Test("a payload closing the raw string early is rejected")
  func rawStringGuardRejectsTripleQuote() throws {
    let unsafe = ParityFixtureEmitter.Fixture(
      name: "unsafe", purpose: "control", scenarioJSON: "{}",
      responses: ["\"\"\""], transcript: [], callCount: 0)

    #expect(throws: ParityFixtureError.self) {
      _ = try ParityFixtureEmitter.kotlinSource(from: [unsafe])
    }
  }

  @Test("a safe fixture renders")
  func rawStringGuardAcceptsSafePayload() throws {
    let safe = ParityFixtureEmitter.Fixture(
      name: "safe", purpose: "control", scenarioJSON: "{}",
      responses: [#"{"statement": "ok"}"#], transcript: ["{}"], callCount: 1)

    let source = try ParityFixtureEmitter.kotlinSource(from: [safe])
    #expect(source.contains("internal val safe: Fixture"))
    #expect(source.contains("callCount = 1"))
  }

  // MARK: - Seed plumbing (ADR-023 S3b)

  @Test("an unseeded fixture emits no seed line")
  func unseededFixtureEmitsNoSeedLine() throws {
    // The generated `seed` property is defaulted precisely so an RNG-free
    // fixture's block stays byte-identical to its pre-seam form; if a `seed =`
    // line appeared here, regenerating would rewrite all six existing blocks.
    let unseeded = ParityFixtureEmitter.Fixture(
      name: "unseeded", purpose: "control", scenarioJSON: "{}",
      responses: [], transcript: [], callCount: 0)

    let source = try ParityFixtureEmitter.kotlinSource(from: [unseeded])
    #expect(!source.contains("seed = "))
    // The declaration's defaulted property is what makes the omission compile.
    #expect(source.contains("val seed: ULong? = null,"))
  }

  @Test("a seeded fixture emits its seed as a Kotlin ULong literal")
  func seededFixtureEmitsAULongLiteral() throws {
    let seeded = ParityFixtureEmitter.Fixture(
      name: "seeded", purpose: "control", scenarioJSON: "{}",
      responses: [], transcript: [], callCount: 0, seed: 42)

    let source = try ParityFixtureEmitter.kotlinSource(from: [seeded])
    // `uL`, not a bare integer: Kotlin infers `Int` otherwise and the
    // `ULong?` property would not typecheck.
    #expect(source.contains("seed = 42uL,"))

    // The upper bound too: `UInt64.max` exceeds `Long.MAX_VALUE`, so a
    // formatter that round-tripped through a signed type would emit a negative
    // literal here and the generated file would not compile.
    let maxSeeded = ParityFixtureEmitter.Fixture(
      name: "seeded", purpose: "control", scenarioJSON: "{}",
      responses: [], transcript: [], callCount: 0, seed: UInt64.max)

    #expect(
      try ParityFixtureEmitter.kotlinSource(from: [maxSeeded])
        .contains("seed = 18446744073709551615uL,"))
  }

  @Test("seeding an RNG-free spec is inert: same transcript, seed carried through")
  func seedingAnRNGFreeSpecIsInert() async throws {
    // Covers the claim on `FixtureSpec.seed` that seeding a fixture whose
    // scenario draws nothing changes nothing (the seeded specs themselves cover
    // the other direction). If the transcripts diverged, either the scenario is not
    // RNG-free after all or the seam leaked into a handler that should not draw.
    guard
      let nominal = ParityFixtureEmitter.specs.first(where: { $0.name == "targetScoreRaceNominal" })
    else {
      Issue.record("expected the nominal spec to exist by name")
      return
    }
    let seededSpec = ParityFixtureEmitter.FixtureSpec(
      name: nominal.name, scenarioPath: nominal.scenarioPath, purpose: nominal.purpose,
      overrides: nominal.overrides, seed: 7)

    let unseededRun = try await ParityFixtureEmitter.run(nominal)
    let seededRun = try await ParityFixtureEmitter.run(seededSpec)

    #expect(seededRun.seed == 7)
    #expect(unseededRun.seed == nil)
    #expect(seededRun.transcript == unseededRun.transcript)
  }
}
