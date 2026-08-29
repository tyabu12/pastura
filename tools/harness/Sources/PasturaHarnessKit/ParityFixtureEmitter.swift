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

  /// Runs one spec through the Swift Engine.
  package static func run(_ spec: FixtureSpec) async throws -> Fixture {
    let yaml = try String(contentsOfFile: spec.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)
    let responder = RecordingResponder(
      personas: scenario.personas.map(\.name),
      choiceOptions: try choiceOptions(in: scenario),
      overrides: spec.overrides)

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

  /// The option menu a scenario's `choose` phases offer, for the responder to
  /// answer `.choice` fields from.
  ///
  /// **Why it must be unambiguous.** ``RecordingResponder`` reads the schema
  /// and nothing else — it cannot see which phase is calling — so a scenario
  /// declaring two different menus has no single right answer, and picking one
  /// would silently answer the other phase off-menu, where
  /// `ChooseHandler.validateAction` drops the pairing. Throwing here turns that
  /// into a generation-time failure with the scenario named, rather than a
  /// fixture that runs and scores nothing.
  ///
  /// Nested branches are walked because a `conditional`'s `thenPhases` /
  /// `elsePhases` may hold a `choose`; an options-less `choose` contributes
  /// nothing, matching `OutputSchema.from`, which only marks a field `.choice`
  /// when the phase has options.
  ///
  /// `package` rather than `private` so the ambiguity guard is testable without
  /// authoring a throwaway scenario file on disk.
  package static func choiceOptions(in scenario: Scenario) throws -> [String] {
    var menus: [[String]] = []
    func walk(_ phases: [Phase]) {
      for phase in phases {
        if phase.type == .choose, let options = phase.options, !options.isEmpty,
          !menus.contains(options) {
          menus.append(options)
        }
        walk(phase.thenPhases ?? [])
        walk(phase.elsePhases ?? [])
      }
    }
    walk(scenario.phases)
    guard menus.count <= 1 else {
      throw ParityFixtureError.ambiguousChoiceOptions(scenario.id, menus)
    }
    return menus.first ?? []
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
  /// A scenario declares more than one distinct `choose` option menu, which
  /// the schema-only ``RecordingResponder`` cannot disambiguate.
  case ambiguousChoiceOptions(String, [[String]])

  package var description: String {
    switch self {
    case .notUTF8(let name):
      return "parity fixture '\(name)' encoded to non-UTF-8 bytes"
    case .rawStringUnsafe(let name, let reason):
      return
        "parity fixture '\(name)' cannot be embedded in a Kotlin raw string: it contains \(reason)"
    case .ambiguousChoiceOptions(let scenarioID, let menus):
      let rendered = menus.map { "[\($0.joined(separator: ", "))]" }.joined(separator: " vs ")
      return
        "scenario '\(scenarioID)' declares \(menus.count) distinct choose option menus (\(rendered)); "
        + "the parity responder reads only the schema, so it cannot tell which phase is calling"
    }
  }
}
