import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

// The non-degeneracy sweep for the handlers only an RNG-bearing scenario
// reaches (ADR-023 S3b-2): `eliminate`, `event_inject`, `narrate`, `reflect`,
// `relationship_update`. Split from `+Exercise.swift` for the same reason that
// file was split from the suite — SwiftLint's function-body and file-length
// caps — and because these arms read the transcript per round rather than as
// one flat list.
extension ParityFixtureEmitterTests {
  @Test("every fixture exercises the RNG-bearing handlers it runs, not just their shape")
  func everyFixtureExercisesTheHandlersItDraws() async throws {
    // Same contract as `everyFixtureExercisesVotingNotJustItsShape`, for the
    // handlers a seeded scenario adds. Each of these can run and decide
    // nothing while the transcript keeps its shape: `NarrateHandler` emits no
    // `narration` on an empty log, `EliminateHandler` returns on an empty
    // tally, `RelationshipUpdateHandler` applies dropped votes to nobody, and a
    // `probability:` `event_inject` that misses emits an `event_injected` with
    // no value. Every arm below is keyed on the payload, not on the event.
    //
    // **Derived from the run, never hand-listed by name** — the `runsPhase`
    // rule from the sibling sweep, for the same reason.
    var coverage: [String: Int] = [:]
    for spec in ParityFixtureEmitter.specs {
      let fixture = try await ParityFixtureEmitter.run(spec)
      let rounds = rounds(of: fixture.transcript)
      func runsPhase(_ type: PhaseType) -> Bool {
        fixture.transcript.contains { phaseStarted($0, type) }
      }
      func cover(_ type: PhaseType) { coverage[type.rawValue, default: 0] += 1 }

      if runsPhase(.eliminate) {
        cover(.eliminate)
        expectEliminationDecides(in: fixture, rounds: rounds, label: spec.name)
      }

      if runsPhase(.eventInject) {
        cover(.eventInject)
        expectEventsFireWithoutRepeating(in: fixture, label: spec.name)
      }

      if runsPhase(.narrate) {
        cover(.narrate)
        for (index, round) in rounds.enumerated()
        where round.contains(where: { phaseStarted($0, .narrate) }) {
          #expect(
            round.contains(where: aNonEmptyNarration),
            "\(spec.name): round \(index + 1) ran narrate and produced no commentary")
        }
      }

      if runsPhase(.reflect) {
        cover(.reflect)
        expectEveryReflectionHasContent(in: fixture, label: spec.name)
      }

      if runsPhase(.relationshipUpdate) {
        cover(.relationshipUpdate)
        #expect(
          fixture.transcript.contains(where: aMovedRelationship),
          "\(spec.name): relationship_update ran and no affinity ever moved")
      }
    }
    for type in [PhaseType.eliminate, .eventInject, .narrate, .reflect, .relationshipUpdate] {
      #expect(
        coverage[type.rawValue, default: 0] > 0,
        "no fixture ran a \(type.rawValue) phase — that assertion passed vacuously")
    }
  }

  /// Guards the `seed:` contract on `ParityFixtureEmitter.FixtureSpec` from
  /// both sides: a scenario that draws must be seeded, or the golden freezes
  /// one system-RNG outcome and the Kotlin replay cannot rebuild it; a scenario
  /// that draws nothing must not be, or the seed claims a determinism the
  /// transcript cannot check. Replaces the pre-S3b-2 `everySpecIsUnseeded`,
  /// and derives "draws" from the loaded scenario rather than naming specs.
  @Test("a spec is seeded exactly when its scenario draws from the RandomSource")
  func seededSpecsAreExactlyTheDrawingOnes() throws {
    var seeded = 0
    for spec in ParityFixtureEmitter.specs {
      let yaml = try String(contentsOfFile: spec.scenarioPath, encoding: .utf8)
      let scenario = try ScenarioLoader().load(yaml: yaml)
      let draws = scenarioDraws(scenario.phases)
      #expect(
        (spec.seed != nil) == draws,
        "\(spec.name): scenario draws = \(draws), seed = \(String(describing: spec.seed))")
      if spec.seed != nil { seeded += 1 }
    }
    #expect(seeded > 0, "no spec is seeded — the seeded replay branch is unexercised again")
  }

  /// Every hand-pinned override answers the schema of the call it landed on.
  ///
  /// `overrides` is positional, and the index is pinned by hand from a count of
  /// the calls before it. A vote answer that lands one call early is a
  /// well-formed JSON object the parser accepts and the `reflect` phase
  /// ignores — nothing downstream names the misalignment, and every later
  /// override is off by the same amount. Checked on the run the overrides
  /// actually shaped (elimination changes the call count of every later
  /// round), not on an unoverridden replay.
  ///
  /// Only a parseable object is checked: the structural control's multi-object
  /// payload is unparseable by construction, and that is its point.
  @Test("every override answers the schema of the call it lands on")
  func everyOverrideAnswersTheSchemaItLandsOn() async throws {
    for spec in ParityFixtureEmitter.specs where !spec.overrides.isEmpty {
      let run = try await ParityFixtureEmitter.exercise(spec)
      for (index, payload) in spec.overrides.sorted(by: { $0.key < $1.key }) {
        try #require(
          index < run.answeredFields.count,
          "\(spec.name): override \(index) is past the run's last call (\(run.answeredFields.count))"
        )
        guard
          let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        else { continue }
        let declared = Set(run.answeredFields[index])
        #expect(
          declared.isSubset(of: Set(object.keys)),
          "\(spec.name): override \(index) answers \(object.keys.sorted()) but the call declared \(declared.sorted())"
        )
      }
    }
  }

  // MARK: - Per-handler arms

  /// Every round that ran `eliminate` eliminated somebody, and at least one
  /// vote in the run had a unique winner.
  ///
  /// The second half: a vote every round can leave to the name tie-break is
  /// not a vote the fixture measures — with every tally 1-1-1-1-1, `eliminate`
  /// and `vote_winner` are decided by `RankingOrder` alone, whatever the votes
  /// said. Required where a vote *decides* something (elimination) rather than
  /// for every voting fixture, because the two `target_score_race` fixtures
  /// tie every round by design and score through the tally, not a winner.
  private func expectEliminationDecides(
    in fixture: ParityFixtureEmitter.Fixture, rounds: [[String]], label: String
  ) {
    for (index, round) in rounds.enumerated()
    where round.contains(where: { phaseStarted($0, .eliminate) }) {
      #expect(
        round.contains { $0.contains("\"event\":\"elimination\"") },
        "\(label): round \(index + 1) ran eliminate and eliminated nobody — the tally was empty")
    }
    #expect(
      fixture.transcript.contains(where: aDecisiveTally),
      "\(label): no vote ever had a unique winner — every outcome was the name tie-break's")
  }

  /// At least one `event_inject` fired, and no injected text repeated — the
  /// `no_repeat` contract where the scenario declares it, and trivially true of
  /// a single-fire scenario, so it is not gated on the flag.
  private func expectEventsFireWithoutRepeating(
    in fixture: ParityFixtureEmitter.Fixture, label: String
  ) {
    let injected = fixture.transcript.compactMap(injectedEventValue)
    #expect(!injected.isEmpty, "\(label): no event_inject ever fired — every roll missed")
    #expect(
      Set(injected).count == injected.count, "\(label): an injected event repeated: \(injected)")
  }

  /// Every `reflect` output carries a non-empty note.
  private func expectEveryReflectionHasContent(
    in fixture: ParityFixtureEmitter.Fixture, label: String
  ) {
    let notes = fixture.transcript.filter {
      $0.contains("\"phase_type\":\"reflect\"") && $0.contains("\"agent_output\"")
    }
    #expect(!notes.isEmpty, "\(label): reflect ran and no agent produced a note")
    #expect(
      notes.allSatisfy { !$0.contains(":\"\"") },
      "\(label): a reflect output carries an empty field")
  }

  // MARK: - Transcript predicates

  private func phaseStarted(_ line: String, _ type: PhaseType) -> Bool {
    line.contains("\"event\":\"phase_started\"")
      && line.contains("\"phase_type\":\"\(type.rawValue)\"")
  }

  /// The transcript split at each `round_started`, so a per-round arm can ask
  /// whether the phase that ran in that round also decided something there.
  private func rounds(of transcript: [String]) -> [[String]] {
    var rounds: [[String]] = []
    for line in transcript {
      if line.contains("\"event\":\"round_started\"") { rounds.append([]) }
      if !rounds.isEmpty { rounds[rounds.count - 1].append(line) }
    }
    return rounds
  }

  /// Whether one line is a `vote_results` with a unique top tally.
  private func aDecisiveTally(_ line: String) -> Bool {
    guard line.contains("\"event\":\"vote_results\""),
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
      let tallies = object["tallies"] as? [String: Int], let top = tallies.values.max()
    else { return false }
    return tallies.values.filter { $0 == top }.count == 1
  }

  /// The value of an `event_injected` line that fired, `nil` for a miss.
  private func injectedEventValue(_ line: String) -> String? {
    guard line.contains("\"event\":\"event_injected\""),
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
      let value = object["value"] as? String, !value.isEmpty
    else { return nil }
    return value
  }

  private func aNonEmptyNarration(_ line: String) -> Bool {
    line.contains("\"event\":\"narration\"") && !line.contains("\"value\":\"\"")
  }

  /// Whether one line is a `relationship_update` carrying at least one
  /// affinity — an empty map is the shape dropped votes leave behind.
  private func aMovedRelationship(_ line: String) -> Bool {
    guard line.contains("\"event\":\"relationship_update\""),
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
      let relationships = object["relationships"] as? [String: [String: Int]]
    else { return false }
    return relationships.values.contains { !$0.isEmpty }
  }

  /// Whether a phase list, branches included, holds a handler that draws from
  /// the `RandomSource`: `assign random_one` or `event_inject` — the two
  /// consumers `PhaseContext.random` has (`Engine/RandomSource.swift`).
  private func scenarioDraws(_ phases: [Phase]) -> Bool {
    phases.contains { phase in
      (phase.type == .assign && phase.target == .randomOne)
        || phase.type == .eventInject
        || scenarioDraws(phase.thenPhases ?? []) || scenarioDraws(phase.elsePhases ?? [])
    }
  }
}
