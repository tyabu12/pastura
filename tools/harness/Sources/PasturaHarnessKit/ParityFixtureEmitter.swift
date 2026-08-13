import Foundation
import PasturaCore

/// Emits the ADR-023 Stage-4 cross-language parity fixtures: for one scenario
/// and one scripted-response plan, the scenario, the exact model answers, and
/// the Swift Engine's resulting event transcript, frozen as Kotlin constants.
///
/// **Why the transcript is `EventLine`, not `SimulationEvent`.** Swift's
/// `SimulationEvent` is `Sendable, Equatable` — it has no `Codable`
/// conformance, and adding one for a harness would put a wire contract on a
/// callback-boundary type that nothing in production serializes (ADR-023 §12
/// PR0-b, and the condition-1 tag-form ruling). ``EventLineMapper`` already
/// defines this repo's transcript surface, is already reviewed, and already
/// carries a compile-time canary — so the parity harness reuses it rather than
/// authoring a second projection.
///
/// **Why it is deterministic.** `EventLineMapper.map` takes `t` and `attempt`
/// as parameters rather than reading a clock, so pinning both to zero removes
/// every timestamp and identity source from the transcript. The two events the
/// mapper drops are dropped for cause, not convenience: both engines emit
/// `agentOutputStream` with payloads that differ by construction (Swift runs a
/// partial-output extractor over each chunk, Kotlin forwards the raw text), and
/// both emit `roundCheckpoint` carrying a full `SimulationState` whose parity
/// the Models rung already covers.
///
/// **Why the scenario crosses as JSON.** `ScenarioLoader` has no Kotlin port
/// yet (ADR-023 Stage 3), so re-parsing the YAML on the Kotlin side would
/// measure a loader that does not exist. Encoding the loaded `Scenario`
/// isolates Stage 4 from that gap; loader parity becomes its own obligation
/// when the port lands.
package enum ParityFixtureEmitter {

  /// One scenario plus the response plan that drives it.
  package struct FixtureSpec: Sendable {
    /// Kotlin constant prefix and test label.
    package let name: String
    /// Repo-relative scenario path, resolved against the current directory.
    package let scenarioPath: String
    /// What this fixture is for, carried into the generated file.
    package let purpose: String
    /// Answers replacing the derived one at a given 0-based call index — see
    /// ``RecordingResponder``. Empty for a nominal run.
    package let overrides: [Int: String]

    package init(
      name: String, scenarioPath: String, purpose: String, overrides: [Int: String] = [:]
    ) {
      self.name = name
      self.scenarioPath = scenarioPath
      self.purpose = purpose
      self.overrides = overrides
    }
  }

  /// A completed Swift-side run, ready to freeze.
  package struct Fixture: Sendable, Equatable {
    package let name: String
    package let purpose: String
    /// The loaded `Scenario`, JSON-encoded with sorted keys.
    package let scenarioJSON: String
    /// Model answers in call order — what Kotlin's `ScriptedLLMBackend` replays.
    ///
    /// **Positional, with no per-call alignment key.** If the two engines
    /// issue different call counts mid-run, every later answer shifts and the
    /// downstream transcript diff becomes noise about alignment rather than
    /// about the engines.
    ///
    /// A parallel *tag* list (`<agent>/<phase>/<attempt>`) was once planned to
    /// localize the first drift; it is deliberately not implemented, because a
    /// tag labels the drift rather than preventing it, and localization already
    /// exists — `TranscriptComparator` sets `Report.desynced` at the first
    /// uncovered structural difference and leads its report with "fix the first
    /// one and re-run", while ``callCount`` catches the total. The real
    /// constraint, found while re-arming the structural control (#1458), is
    /// that a surplus must be **reabsorbed**: either the divergent turn is the
    /// run's last, so the extra calls fall into the replay padding, or the
    /// following indices deliberately burn a matching surplus on the other
    /// engine. Keying responses by `<agent>/<phase>/<attempt>` instead of by
    /// position would fix that; tagging would not. It is a schema change.
    package let responses: [String]
    /// One JSON object per surviving event, in emission order.
    package let transcript: [String]
    /// Backend calls the Swift Engine issued. A first-class field because a
    /// divergence where one engine retries and the other does not is a
    /// retry-count divergence the transcript alone cannot show — today the
    /// multi-object salvage, before ADR-021's Amendment the schema guard.
    package let callCount: Int

    /// Explicit because the implicit memberwise init is `internal`, and the
    /// raw-string safety guard is tested from the sibling test module.
    package init(
      name: String, purpose: String, scenarioJSON: String,
      responses: [String], transcript: [String], callCount: Int
    ) {
      self.name = name
      self.purpose = purpose
      self.scenarioJSON = scenarioJSON
      self.responses = responses
      self.transcript = transcript
      self.callCount = callCount
    }
  }

  /// The fixtures this repo freezes, in emission order.
  ///
  /// `target_score_race` is one of three bundled presets that are fully
  /// deterministic — neither engine injects RNG, and both rely on degenerate
  /// inputs rather than seeding — and it is the only one of those three that
  /// exercises `conditional`.
  ///
  /// "Exercises `conditional`" means the **branch**, not merely the node: an
  /// earlier draft of the responder made every vote a self-vote, so every tally
  /// was empty, every score stayed 0, and `max_score >= 3` was false in all four
  /// evaluations — the phase ran and decided nothing. A fixture can look like a
  /// full run while its whole scoring half is frozen, so
  /// `nominalRunExercisesVotingNotJustItsShape` asserts the non-degenerate
  /// outcome rather than leaving it to the responder's arithmetic.
  package static let specs: [FixtureSpec] = [
    FixtureSpec(
      name: "targetScoreRaceNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Happy path. Every answer is well-formed and non-empty, so a green \
        comparison here means the two engines agree with an empty divergence \
        ledger — which is Stage 4's actual goal, not merely that the harness runs.
        """
    ),
    FixtureSpec(
      name: "targetScoreRaceDivergent",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Negative control. A ledger whose entries never fire ships unexercised, \
        so this fixture drives documented divergences on purpose and the parity \
        suite fails if one stops firing.

        **It drives a VALUE divergence only, by design rather than by loss.** \
        It used to drive one of each entry kind: calls 0-2 answer the first \
        agent's schema-declaring `speak_all` turn with present-but-empty \
        canonical fields across the whole retry window, which Swift returned as \
        an `agentOutput` while Kotlin's parser guard exhausted retries into a \
        `turnSkipped`. ADR-021 § Amendment 2026-08-06 resolved that — both \
        engines now skip — retiring `SCHEMA_GUARD_POSITION`. The empty-field \
        overrides are kept because they still exercise the retry window \
        identically on both sides.

        The structural arm was re-armed in `parityStructuralControl` instead, \
        because the surviving scriptable divergence costs Kotlin two extra \
        backend calls and `responses` is positional — the surplus has to land \
        on the run's LAST call, which here is a `vote` whose loss cascades \
        through the tally. So do not read a clean structural comparison here as \
        evidence the structural path is exercised; \
        `someFixtureDrivesBothEntryKinds` is what keeps that honest.

        The float-valued key below is this fixture's arm. Swift normalizes \
        `1.0` to "1" because `NSNumber.stringValue` drops the `.0`; Kotlin \
        preserves the literal as "1.0" — the VALUE divergence \
        `JSONResponseParser.kt` routes to Stage 4 to rule on.
        """,
      overrides: [
        0: #"{"statement": "", "inner_thought": ""}"#,
        1: #"{"statement": "", "inner_thought": ""}"#,
        2: #"{"statement": "", "inner_thought": ""}"#,
        3: #"{"statement": "s", "inner_thought": "t", "confidence": 1.0}"#
      ]
    ),
    FixtureSpec(
      name: "parityStructuralControl",
      scenarioPath: "tools/harness/Fixtures/parity_structural.yaml",
      purpose: """
        Structural negative control. The sibling divergent fixture drives a \
        VALUE divergence only; this one exists so the ledger's kind-coverage \
        guard has a `Structural` entry to hold, and so a divergence class and \
        its entries cannot be deleted together unnoticed — the way ADR-021 \
        § Amendment 2026-08-06 retired `SCHEMA_GUARD_POSITION` and silently \
        cost the control its only structural arm.

        Call 1 drives it. Swift's schema-guarded multi-object salvage (#907) \
        accepts the first object when every expected key is present and \
        non-empty, returning an `agentOutput` after ONE backend call. Kotlin's \
        `extractFirstJsonObject` returns object-like residue unchanged, so the \
        parse fails and the turn exhausts its retry budget into a `turnSkipped` \
        after THREE. Paired parser tests fed byte-identical input pin both \
        behaviours, so neither can drift silently.

        **Why its own scenario rather than an override on the sibling.** \
        `Fixture.responses` is positional, so Kotlin's two surplus calls \
        consume whatever answers follow; placed mid-run they shift every later \
        turn and the diff becomes noise about alignment rather than about the \
        engines. Here the divergent turn is the run's LAST, so the surplus \
        falls into the parity suite's padding. The cost is pinned instead of \
        hidden: the two engines issue different call counts, and that is \
        asserted rather than excused.

        Call 0 carries the float-valued key as well, so this fixture drives one \
        divergence of EACH entry kind by itself — kind coverage then holds \
        per-fixture rather than only across the set, for one extra override.
        """,
      overrides: [
        0: #"{"statement": "s", "inner_thought": "t", "confidence": 1.0}"#,
        1: #"{"statement": "hello", "inner_thought": "thinking"}{"stray": 1}"#
      ]
    )
  ]

  /// Runs one spec through the Swift Engine.
  package static func run(_ spec: FixtureSpec) async throws -> Fixture {
    let yaml = try String(contentsOfFile: spec.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)
    let responder = RecordingResponder(
      personas: scenario.personas.map(\.name), overrides: spec.overrides)

    var transcript: [String] = []
    // No `detector:` — deliberate, and the inverse of what `HarnessRunner` does
    // eleven files away (it injects one precisely so `language_mismatch` is not
    // 0 by construction, #1234). Two reasons it must stay omitted here:
    // `HarnessLanguageDetector` wraps `NLLanguageRecognizer`, an OS-version-
    // dependent classifier that would make the golden vary by host; and it has
    // no Kotlin counterpart yet, so any event it produced would be a divergence
    // about the harness rather than about the engines. `parityRunEmitsNoLanguageMismatch`
    // guards the omission.
    let stream = SimulationRunner().run(
      scenario: scenario, llm: responder, suspendController: SuspendController())
    for await event in stream {
      guard let line = EventLineMapper.map(normalize(event), t: 0, attempt: 0) else { continue }
      transcript.append(try JSONL.encode(line))
    }

    return Fixture(
      name: spec.name,
      purpose: spec.purpose,
      scenarioJSON: try encodeScenario(scenario),
      responses: responder.recordedResponses,
      transcript: transcript,
      callCount: responder.callCount)
  }

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
  private static func normalize(_ event: SimulationEvent) -> SimulationEvent {
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

  /// Repo-relative path of the generated Kotlin file, named once so the CLI,
  /// the drift gate, and the docs cannot disagree.
  package static let generatedPath =
    "shared/engine/src/commonTest/kotlin/com/pastura/engine/ParityGolden.kt"

  /// The command that regenerates it, quoted in the file header and in the
  /// drift-gate failure message.
  package static let regenerateCommand = "swift run pastura-harness parity-emit --write"

  /// Encodes the scenario with sorted keys so `--check` reports real drift
  /// rather than dictionary-order churn.
  private static func encodeScenario(_ scenario: Scenario) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(scenario)
    guard let json = String(data: data, encoding: .utf8) else {
      throw ParityFixtureError.notUTF8(scenario.id)
    }
    return json
  }
}

/// Why a parity fixture could not be produced.
package enum ParityFixtureError: Error, CustomStringConvertible {
  /// A scenario encoded to bytes that are not valid UTF-8.
  case notUTF8(String)
  /// A fixture contains bytes a Kotlin raw string cannot carry verbatim.
  case rawStringUnsafe(String, String)

  package var description: String {
    switch self {
    case .notUTF8(let name):
      return "parity fixture '\(name)' encoded to non-UTF-8 bytes"
    case .rawStringUnsafe(let name, let reason):
      return
        "parity fixture '\(name)' cannot be embedded in a Kotlin raw string: it contains \(reason)"
    }
  }
}
