import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

// The suspend arm (ADR-023 S5, #1625), split from the suite file for the same
// reason `ParityFixtureEmitterTests+Cancel.swift` was: these cases assert on
// a property (`callCount`, the absence of `turn_skipped`) no other emitter
// case checks, so folding them into the main suite would bury the seam's own
// claim among unrelated assertions.
extension ParityFixtureEmitterTests {

  /// The registered suspending fixture, so every case below reads the same
  /// spec the generator freezes rather than a hand-built twin of it.
  private func suspendSpec() throws -> ParityFixtureEmitter.FixtureSpec {
    try #require(
      ParityFixtureEmitter.specs.first { $0.name == "paritySuspendPreservesRetryBudget" },
      "the suspending fixture is no longer registered in `specs`")
  }

  @Test("suspend cycles are invisible to the retry budget: the full turn survives")
  func suspendCyclesPreserveTheRetryBudget() async throws {
    let spec = try suspendSpec()
    #expect(
      spec.suspendBeforeResponse == [1: 1, 2: 1, 3: 1],
      "the schedule moved; every assertion below is written against it")

    let fixture = try await ParityFixtureEmitter.run(spec)

    // 9 = 6 answered calls (2 phases x 2 agents + the 2 extra attempts
    // `overrides` burns on Bo's phase-0 turn) + 3 suspend re-issues. If a
    // suspend had been charged to `LLMCaller.maxRetries`, Bo's turn would
    // exhaust its budget one attempt early and never reach the accepted
    // answer, which would also change this total.
    #expect(fixture.callCount == 9)
    // `#require`, not `#expect`: a shortened `responses` must report, not trap
    // on the subscripts below and take the serialized suite's results with it.
    try #require(fixture.responses.count == 6)
    #expect(fixture.responses[1] == ParityFixtureEmitter.unparseableProbe)
    #expect(fixture.responses[2] == ParityFixtureEmitter.unparseableProbe)

    // The turn that would have been skipped had a suspend consumed the
    // budget. Its absence is the direct claim; `callCount` above is the
    // corroborating aggregate.
    #expect(
      !fixture.transcript.contains { $0.contains(#""event":"turn_skipped""#) },
      "a suspend cycle was charged against the retry budget and skipped the turn")
    #expect(
      fixture.transcript.last?.contains(#""event":"simulation_completed""#) == true,
      "the run did not reach its normal terminal event")

    // Bo's committed outputs across BOTH `speak_all` phases — one each. The
    // retried attempts on his phase-0 turn are invisible here (only the
    // accepted answer is mapped), so a fork of that turn into more than one
    // committed output would push this above 2.
    let bosOutputs = fixture.transcript.filter {
      $0.contains(#""event":"agent_output""#) && $0.contains(#""agent":"Bo""#)
        && $0.contains(#""phase_type":"speak_all""#)
    }
    #expect(bosOutputs.count == 2, "Bo speaks in both speak_all phases; expected one line each")
  }

  @Test("a suspend scheduled on an unreachable response index fails loudly")
  func unreachableSuspendScheduleIsRejected() async throws {
    // Same silent-failure shape `unreachableCancelTriggerIsRejected` guards on
    // the cancellation seam: with no check, the run simply completes and the
    // generated golden freezes a `suspendBeforeResponse` map the replay could
    // never exhaust.
    let spec = ParityFixtureEmitter.FixtureSpec(
      name: "unreachableSuspend",
      scenarioPath: try suspendSpec().scenarioPath,
      purpose: "test-only: a response index this scenario's run never reaches",
      suspendBeforeResponse: [99: 1])

    await #expect {
      _ = try await ParityFixtureEmitter.run(spec)
    } throws: { error in
      if case ParityFixtureError.suspendNeverFired = error {
        return true
      } else {
        return false
      }
    }
  }

  @Test(
    "the suspending fixture's generated Kotlin carries its schedule; a nominal fixture's does not")
  func suspendScheduleAppearsOnlyOnTheSuspendingFixturesKotlinBlock() async throws {
    let suspending = try await ParityFixtureEmitter.run(try suspendSpec())
    let nominal = try #require(
      ParityFixtureEmitter.specs.first(where: { $0.name == "targetScoreRaceNominal" }))
    let nominalFixture = try await ParityFixtureEmitter.run(nominal)

    // Order-dependent: the nominal fixture must be LAST — the block scoping
    // below falls back to "everything after the suspending block", which
    // would swallow it if the order were reversed (red, not green, but for
    // the wrong reason).
    let source = try ParityFixtureEmitter.kotlinSource(from: [suspending, nominalFixture])
    #expect(source.contains("suspendBeforeResponse = mapOf(1 to 1, 2 to 1, 3 to 1),"))

    // The nominal fixture's own block must not carry the field at all — only
    // its shared `Fixture` class declaration should mention the property
    // name, via the defaulted parameter.
    let nominalBlockStart = try #require(
      source.range(of: "internal val targetScoreRaceNominal: Fixture = Fixture("))
    let nominalBlock = source[nominalBlockStart.lowerBound...]
    let nominalBlockEnd = nominalBlock.range(of: "\n    )")
    let scopedNominalBlock =
      nominalBlockEnd.map { String(nominalBlock[..<$0.upperBound]) } ?? String(nominalBlock)
    #expect(!scopedNominalBlock.contains("suspendBeforeResponse ="))
  }
}
