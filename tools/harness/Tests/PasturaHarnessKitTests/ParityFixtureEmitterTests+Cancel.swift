import Foundation
import PasturaCore
import Testing

@testable import PasturaHarnessKit

// The cancellation arm (ADR-023 S4, #1622), split from the suite file for the
// same reason `+Exercise.swift` and `+SeededExercise.swift` were — SwiftLint's
// file-length cap — and because these cases assert on the transcript's TAIL,
// where every other emitter case asserts on its body.
extension ParityFixtureEmitterTests {

  /// The registered cancelling fixture, so both cases below read the same spec
  /// the generator freezes rather than a hand-built twin of it.
  ///
  /// Looked up by name and required to exist: a spec silently dropped from the
  /// roster would otherwise make every case here vacuous, which is the failure
  /// shape the sibling sweeps' "derived from the run, never hand-listed" rule
  /// exists to avoid.
  private func cancelSpec() throws -> ParityFixtureEmitter.FixtureSpec {
    try #require(
      ParityFixtureEmitter.specs.first { $0.name == "parityCancelConditional" },
      "the cancelling fixture is no longer registered in `specs`")
  }

  @Test("the cancelling fixture's transcript ends at the cancellation, mid-branch")
  func cancellingFixtureFreezesTheCancellationTail() async throws {
    let spec = try cancelSpec()
    #expect(
      spec.cancelAfterPhaseCompleted == [1, 0],
      "the trigger moved; every assertion below is written against [1, 0]")

    let fixture = try await ParityFixtureEmitter.run(spec)

    // The four claims are asserted separately rather than as one transcript
    // equality: an equality pin would redden on any unrelated payload change
    // (a persona rename, a prompt reword) and say nothing about *which* of the
    // four properties broke. These are the properties #1622 changed.
    //
    // 1. The tail is the cancellation, and it is LAST. Before the fix the run
    //    could emit a second `.error(.cancelled)` on the pause path, so
    //    "contains an error line" is not the claim — "ends with exactly one" is.
    #expect(
      fixture.transcript.last?.contains(#""error":"cancelled""#) == true,
      "the last line is not the cancellation error: \(fixture.transcript.last ?? "<empty>")")
    #expect(
      fixture.transcript.filter { $0.contains(#""event":"error""#) }.count == 1,
      "the run emitted more than one error event")

    // 2. The branch's FIRST sub-phase completed — the cancel lands after it,
    //    not instead of it, which is what makes the fixture a mid-branch cut
    //    rather than a cut before the branch ran at all.
    #expect(
      fixture.transcript.contains(where: aPhaseCompleted(path: "[1,0]")),
      "the branch's first sub-phase never completed, so the trigger never fired")

    // 3. The outer `conditional` started but must NOT complete. This is the
    //    exact regression #1622 fixed: `ConditionalHandler.runBranch` used to
    //    RETURN on cancellation, which read to the runner as "the branch
    //    finished" and emitted `phase_completed [1]` for work that was cut
    //    short.
    #expect(
      fixture.transcript.contains(where: aPhaseStarted(path: "[1]")),
      "the conditional never started — the fixture is not exercising a branch")
    #expect(
      !fixture.transcript.contains(where: aPhaseCompleted(path: "[1]")),
      "the cut-short conditional still reports `phase_completed [1]` (#1622's regression)")

    // 4. The branch's SECOND sub-phase never ran, and the run never completed.
    //    `[1, 1]` is a template `summarize`, so it issues no backend call —
    //    its absence has to be read off the transcript, not off `callCount`.
    #expect(
      !fixture.transcript.contains(where: aPhaseStarted(path: "[1,1]")),
      "the branch's second sub-phase started after the cancellation")
    #expect(
      !fixture.transcript.contains(where: { $0.contains(#""event":"simulation_completed""#) }),
      "a cancelled run reported `simulation_completed`")
  }

  @Test("a cancel trigger no run emits fails loudly instead of completing")
  func unreachableCancelTriggerIsRejected() async throws {
    // The silent failure this guards: the emitter simply runs to completion and
    // freezes a golden with a `simulation_completed` tail, which looks like a
    // healthy fixture while measuring no cancellation at all. Nothing
    // downstream would name it — the Kotlin replay would agree with it, because
    // it would not cancel either.
    let spec = ParityFixtureEmitter.FixtureSpec(
      name: "unreachableTrigger",
      scenarioPath: try cancelSpec().scenarioPath,
      purpose: "test-only: a phase path this scenario has no phase at",
      cancelAfterPhaseCompleted: [9, 9])

    await #expect(throws: ParityFixtureError.self) {
      _ = try await ParityFixtureEmitter.run(spec)
    }
  }

  // MARK: - Line predicates

  /// A `phase_started` line at `path`, rendered as the JSONL encoder writes it.
  ///
  /// Keyed on the event name AND the path together: `"phase_path":[1]` alone
  /// would also be satisfied by a `phase_completed`, which is the very
  /// distinction case 3 above turns on.
  private func aPhaseStarted(path: String) -> (String) -> Bool {
    { $0.contains(#""event":"phase_started""#) && $0.contains("\"phase_path\":\(path)") }
  }

  /// A `phase_completed` line at `path`. See ``aPhaseStarted(path:)``.
  private func aPhaseCompleted(path: String) -> (String) -> Bool {
    { $0.contains(#""event":"phase_completed""#) && $0.contains("\"phase_path\":\(path)") }
  }
}
