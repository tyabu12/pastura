import Foundation
import PasturaCore

// Split from `ParityFixtureEmitter.swift` when the suspend seam (S5, #1625)
// pushed that file over SwiftLint's `file_length` cap. `normalize` has no
// dependency on the emitter's private storage — it is a pure function over
// one event — so it moves cleanly; `exercise(_:)`, which calls it, stays
// behind in the main file.
extension ParityFixtureEmitter {

  /// Drops the payload fields no cross-language comparison could survive.
  ///
  /// Pinning `EventLineMapper`'s `t` and `attempt` removes the harness's own
  /// clock reads, but two payload-internal fields remain, for different
  /// reasons — one non-deterministic, one structurally absent on the far side:
  ///
  /// - **`inferenceCompleted.durationSeconds`** is measured per call. Left
  ///   alone it changes on every run, so `--check` would report drift against
  ///   itself and the two engines could never agree. `tokenCount` needs no arm:
  ///   this responder reports none, and the Kotlin fixtures script none either
  ///   — if that ever changes, the mismatch surfaces as a parity diff rather
  ///   than as flakiness.
  /// - **`agentOutput.rawText`** has no Kotlin counterpart at all;
  ///   `TurnOutput.kt`'s class KDoc records the omission as a deliberate
  ///   Engine-port decision, not a Stage-4 one. Keeping it would put a
  ///   `raw_text` diff on **every** `agent_output` — 24 in the nominal
  ///   fixture — each pinning a string `responses` already freezes verbatim, so
  ///   the ledger would carry two dozen entries measuring a documented
  ///   model-port decision in place of engine behaviour.
  ///
  ///   What it costs, rather than "nothing is lost": `responses` is the
  ///   authority on what the model **offered**, not on which offer a turn
  ///   **accepted**, and `attempt` is pinned to 0 on every line — so `rawText`
  ///   was the last per-event record of retry outcome. What compensates is
  ///   `callCount` (a whole-run aggregate two offsetting changes could cancel)
  ///   and the paired `JSONResponseParser` tests in both languages. That is
  ///   weaker than a per-event record, and is the price of comparing a field
  ///   one side does not model.
  ///
  /// Deliberately an `if case` chain rather than an exhaustive `switch`: this
  /// is a narrow denylist, and a new case is normalization-free until someone
  /// shows otherwise. The exhaustiveness obligation belongs to
  /// `EventLineMapper`, which already carries it.
  static func normalize(_ event: SimulationEvent) -> SimulationEvent {
    if case .inferenceCompleted(let agent, _, let tokenCount) = event {
      return .inferenceCompleted(agent: agent, durationSeconds: 0, tokenCount: tokenCount)
    }
    if case .agentOutput(let agent, let output, let phaseType) = event {
      return .agentOutput(
        agent: agent, output: TurnOutput(fields: output.fields, rawText: nil),
        phaseType: phaseType)
    }
    return event
  }
}
