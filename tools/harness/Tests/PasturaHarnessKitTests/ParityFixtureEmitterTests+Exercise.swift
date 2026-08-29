import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

// The per-phase non-degeneracy sweep, split out so the suite file stays under
// SwiftLint's file-length cap as fixtures and phase arms accumulate.
extension ParityFixtureEmitterTests {
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
    var choosingFixtures = 0
    var assigningFixtures = 0
    for spec in ParityFixtureEmitter.specs {
      let fixture = try await ParityFixtureEmitter.run(spec)

      // Not every fixture scores: `parityStructuralControl` is a single
      // `speak_all` turn pair with no vote, no `score_calc` and no
      // `conditional`, so the assertions below would fail there for the right
      // shape and the wrong reason.
      //
      // **Derived from the run, never hand-listed by name** — a name-based skip
      // silently stops covering any fixture added later, the same shape as the
      // `specs.first` scoping above.
      //
      // **One predicate per assertion, not one for all three.** A single
      // vote-keyed guard would skip a fixture running `score_calc` and
      // `conditional` without a `vote` — a shape nothing forbids — while the
      // counter stayed positive on the two `target_score_race` fixtures, so the
      // loss would be silent: the same defect displaced onto one phase type
      // rather than removed.
      func runsPhase(_ type: String) -> Bool {
        fixture.transcript.contains {
          $0.contains("\"event\":\"phase_started\"") && $0.contains("\"phase_type\":\"\(type)\"")
        }
      }

      if runsPhase("vote") {
        votingFixtures += 1
        #expect(
          fixture.transcript.contains(where: aNonEmptyTally),
          "\(spec.name): every tally is empty — the votes are dropped, probably as self-votes")
      }

      if runsPhase("score_calc") {
        scoringFixtures += 1
        #expect(
          fixture.transcript.contains(where: aScoreOffZero),
          "\(spec.name): no score ever moved off zero")
      }

      if runsPhase("choose") {
        choosingFixtures += 1
        try expectEveryPayoffRowFires(in: fixture, label: spec.name)
      }

      if runsPhase("assign") {
        assigningFixtures += 1
        #expect(
          fixture.transcript.contains(where: aResolvedSharedAssignment),
          "\(spec.name): every shared_assignment carries an empty value — the topic never resolved")
      }

      if runsPhase("conditional") {
        branchingFixtures += 1
        #expect(
          fixture.transcript.contains(where: aTakenThenBranch),
          "\(spec.name): the then-branch is never taken — the node runs but decides nothing")
      }
    }
    // One counter per assertion: a shared one would let a surviving fixture mask
    // the case where some other phase type stopped being exercised anywhere.
    let coverage = [
      ("vote", votingFixtures), ("score_calc", scoringFixtures),
      ("conditional", branchingFixtures), ("choose", choosingFixtures),
      ("assign", assigningFixtures)
    ]
    for (phase, count) in coverage {
      #expect(count > 0, "no fixture ran a \(phase) phase — that assertion passed vacuously")
    }
  }

  /// Whether one transcript line is a `vote_results` whose tally counted
  /// something — an empty `tallies` means every vote was dropped.
  private func aNonEmptyTally(_ line: String) -> Bool {
    line.contains("\"vote_results\"") && !line.contains("\"tallies\":{}")
  }

  /// Whether one transcript line is a `shared_assignment` that resolved a
  /// topic.
  ///
  /// The vote/choose analogue for the assignment head. `AssignHandler` emits
  /// `sharedAssignment` whatever it resolved, so an empty `value` — a scenario
  /// whose `source:` key is missing from `extraData`, or an `extraData` lost
  /// across the crossing — keeps the event, the shape and the event count while
  /// the round runs with no topic at all. Keyed on the payload for that reason,
  /// not on the event's presence.
  private func aResolvedSharedAssignment(_ line: String) -> Bool {
    line.contains("\"event\":\"shared_assignment\"") && line.contains("\"value\":")
      && !line.contains("\"value\":\"\"")
  }

  /// Whether one transcript line is a `conditional_evaluated` that took the
  /// then-branch.
  private func aTakenThenBranch(_ line: String) -> Bool {
    line.contains("\"conditional_evaluated\",\"result\":true")
  }

  /// Whether one transcript line is a `score_update` carrying a non-zero score.
  ///
  /// Scoped to the `scores` object, and rejecting an empty one. Searching the
  /// whole line for `:0,` could never pass (every EventLine carries
  /// `"attempt":0,`); and `!contains(":0")` alone passes vacuously on
  /// `"scores":{}`, which is a shape this golden demonstrably produces.
  private func aScoreOffZero(_ line: String) -> Bool {
    guard line.contains("\"score_update\""),
      let scores = line.range(of: "\"scores\":{").map({ line[$0.upperBound...] }),
      let end = scores.firstIndex(of: "}")
    else { return false }
    let payload = scores[..<end]
    return !payload.isEmpty && !payload.contains(":0")
  }

  /// The choose analogue of the vote assertion above.
  ///
  /// `ChooseHandler.validateAction` **drops** an off-menu action, so a responder
  /// answering `"action 7"` would leave every pairing rejected while the run kept
  /// its shape and its event count — the silent degeneracy the vote rotation
  /// records. Asserting merely that *some* `pairing_result` appeared would still
  /// pass for a schedule locking every pair to one payoff row, so this demands
  /// the whole table: every `when` row must appear as an ordered action pair.
  ///
  /// **Derived from the fixture's own scenario, never hand-listed** — so a
  /// different menu or a longer table is covered the day it is added.
  private func expectEveryPayoffRowFires(
    in fixture: ParityFixtureEmitter.Fixture, label: String
  ) throws {
    let scenario = try JSONDecoder().decode(Scenario.self, from: Data(fixture.scenarioJSON.utf8))
    let rows = payoffRows(in: scenario.phases)
    #expect(
      !rows.isEmpty,
      "\(label): a choose phase with no pairwise_payoff table — the check below is vacuous")
    for row in rows {
      try #require(row.when.count == 2, "\(label): a payoff row is not a pair")
      #expect(
        fixture.transcript.contains {
          $0.contains("\"event\":\"pairing_result\"")
            && $0.contains("\"action1\":\"\(row.when[0])\"")
            && $0.contains("\"action2\":\"\(row.when[1])\"")
        },
        "\(label): payoff row \(row.when) never fires — the schedule misses a combination")
    }
  }

  /// Every `pairwise_payoff` row a phase list declares, branches included.
  ///
  /// Recursive because a `conditional`'s sub-phases may hold the `score_calc`,
  /// and reading the table from the scenario is what keeps the assertion above
  /// derived rather than hand-listed.
  private func payoffRows(in phases: [Phase]) -> [PayoffRule] {
    phases.flatMap { phase -> [PayoffRule] in
      var rows: [PayoffRule] = []
      if phase.type == .scoreCalc, phase.logic == .pairwisePayoff {
        rows.append(contentsOf: phase.payoff ?? [])
      }
      rows.append(contentsOf: payoffRows(in: phase.thenPhases ?? []))
      rows.append(contentsOf: payoffRows(in: phase.elsePhases ?? []))
      return rows
    }
  }
}
