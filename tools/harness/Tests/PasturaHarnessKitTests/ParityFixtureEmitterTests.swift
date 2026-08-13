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

  // MARK: - RecordingResponder

  @Test("answers are derived from the schema, never from the prompt")
  func responderIgnoresPrompt() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let shortPrompted = RecordingResponder(personas: ["Alice"])
    let longPrompted = RecordingResponder(personas: ["Alice"])

    let fromShortPrompt = try await shortPrompted.generate(system: "s", user: "u", schema: schema)
    let fromLongPrompt = try await longPrompted.generate(
      system: "a much longer system prompt", user: "a much longer user prompt", schema: schema)

    // The guard this defends: `PromptBuilder.formatScoreboard` orders and
    // collapses keys differently in the two engines, so a prompt-keyed
    // responder would hand them different scripts and report the difference as
    // an engine divergence.
    #expect(fromShortPrompt == fromLongPrompt)
  }

  @Test("a vote field resolves to a persona the tally can count")
  func responderResolvesVoteToPersona() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "vote", kind: .string)])
    let responder = RecordingResponder(personas: ["アオイ", "ハルト", "リオ"])

    let first = try await responder.generate(system: "", user: "", schema: schema)
    let second = try await responder.generate(system: "", user: "", schema: schema)

    // Offset by one (see `RecordingResponder.value(for:)`), so call 0 votes for
    // persona 1 rather than persona 0 — which for a real scenario is the
    // difference between a counted vote and a self-vote `exclude_self` drops.
    #expect(first.contains("ハルト"))
    #expect(second.contains("リオ"))
  }

  @Test("an override replaces the derived answer at exactly its call index")
  func responderHonoursOverrideIndex() async throws {
    let schema = OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)])
    let responder = RecordingResponder(personas: ["Alice"], overrides: [1: #"{"statement": ""}"#])

    _ = try await responder.generate(system: "", user: "", schema: schema)
    let overridden = try await responder.generate(system: "", user: "", schema: schema)
    let after = try await responder.generate(system: "", user: "", schema: schema)

    #expect(overridden == #"{"statement": ""}"#)
    // Asserted as the exact value, not as "not empty": the latter passes for any
    // non-empty payload, including a wrongly-indexed one, and would pass
    // vacuously if `derive` changed shape. This pins that the override applied
    // at exactly index 1 and the derivation resumed at call index 2.
    #expect(after == #"{"statement": "statement 2"}"#)
    #expect(responder.callCount == 3)
    #expect(responder.recordedResponses.count == 3)
  }

  // MARK: - Determinism

  // The three cases below run over EVERY spec rather than `specs.first`. They
  // are properties of the emitter, so a representative sample only ever proved
  // them of whichever fixture happened to be declared first — and this file
  // already records one incident (see `everyFixtureExercisesVotingNotJustItsShape`)
  // of a defect surviving in the sibling a single-element scope could not see.

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

      #expect(fixture.callCount == fixture.responses.count, "\(spec.name)")
      #expect(
        fixture.transcript.contains { $0.contains("\"simulation_completed\"") }, "\(spec.name)")
      // Keyed on the spec's own scenario path rather than a hard-coded preset
      // id, which was only ever true of the two `target_score_race` fixtures.
      // `#require`, not `?? ""`: `String.contains("")` is `true`, so an empty
      // fallback would pass vacuously — the shape this file elsewhere refuses.
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
    // Selected BY NAME, not by position. `specs.last` used to be the divergent
    // spec and silently became `parityStructuralControl` when a third fixture
    // was appended — the assertions below then measured the wrong pair and
    // failed for a reason that had nothing to do with their subject. A
    // positional handle into a list that grows is a latent mis-selection.
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

  @Test("every fixture exercises voting, not just its shape")
  func everyFixtureExercisesVotingNotJustItsShape() async throws {
    // The contract `RecordingResponder.value(for:)`'s rotation cannot state for
    // itself: the responder never sees which agent is calling, so it cannot
    // exclude a self-vote by construction. A bare `callIndex % count` made EVERY
    // vote a self-vote for this scenario — all tallies empty, all scores 0,
    // `max_score >= 3` false in all four evaluations — while the run kept the
    // right shape and the right event count, so nothing else here caught it.
    //
    // **Every spec, not `specs.first`.** Scoping this to one fixture is how the
    // second instance survived: `+ 1` repaired the nominal run and left the
    // divergent one on the diagonal, because its retry window shifts the global
    // call stream by two.
    #expect(!ParityFixtureEmitter.specs.isEmpty, "no fixture specs declared")
    var votingFixtures = 0
    var scoringFixtures = 0
    var branchingFixtures = 0
    for spec in ParityFixtureEmitter.specs {
      let fixture = try await ParityFixtureEmitter.run(spec)

      // Not every fixture scores. `parityStructuralControl` is a single
      // `speak_all` turn pair with no vote, no `score_calc` and no
      // `conditional` — the assertions below are meaningless there, and would
      // fail for the right shape and the wrong reason.
      //
      // **Derived from the run, never hand-listed by name.** A name-based skip
      // is the same shape as the `specs.first` scoping this test's own comment
      // records as how the second instance survived: it silently stops covering
      // any fixture added later.
      //
      // **One predicate per assertion, not one for all three.** A single
      // vote-keyed guard would skip a fixture running `score_calc` and
      // `conditional` without a `vote` — a shape nothing forbids — while the
      // counter stayed positive on the two `target_score_race` fixtures, so the
      // loss would be silent. That is the same defect displaced from names onto
      // one phase type rather than removed.
      func runsPhase(_ type: String) -> Bool {
        fixture.transcript.contains {
          $0.contains("\"event\":\"phase_started\"") && $0.contains("\"phase_type\":\"\(type)\"")
        }
      }

      if runsPhase("vote") {
        votingFixtures += 1
        #expect(
          fixture.transcript.contains {
            $0.contains("\"vote_results\"") && !$0.contains("\"tallies\":{}")
          },
          "\(spec.name): every tally is empty — the votes are dropped, probably as self-votes")
      }

      // Scoped to the `scores` object, and rejecting an empty one. Searching the
      // whole line for `:0,` could never pass (every EventLine carries
      // `"attempt":0,`); and `!contains(":0")` alone passes vacuously on
      // `"scores":{}`, which is a shape this golden demonstrably produces.
      if runsPhase("score_calc") {
        scoringFixtures += 1
        #expect(
          fixture.transcript.contains { line in
            guard line.contains("\"score_update\""),
              let scores = line.range(of: "\"scores\":{").map({ line[$0.upperBound...] }),
              let end = scores.firstIndex(of: "}")
            else { return false }
            let payload = scores[..<end]
            return !payload.isEmpty && !payload.contains(":0")
          },
          "\(spec.name): no score ever moved off zero")
      }

      if runsPhase("conditional") {
        branchingFixtures += 1
        #expect(
          fixture.transcript.contains { $0.contains("\"conditional_evaluated\",\"result\":true") },
          "\(spec.name): the then-branch is never taken — the node runs but decides nothing")
      }
    }
    // One counter per assertion: a shared one would let a surviving fixture mask
    // the case where some other phase type stopped being exercised anywhere.
    #expect(votingFixtures > 0, "no fixture ran a vote phase — that assertion passed vacuously")
    #expect(
      scoringFixtures > 0, "no fixture ran a score_calc phase — that assertion passed vacuously")
    #expect(
      branchingFixtures > 0, "no fixture ran a conditional phase — that assertion passed vacuously")
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
}
